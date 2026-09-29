//
// ScrollPoster.swift
// SmoothScroll
// 按显示器刷新节奏插值并派发平滑滚动。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollPoster.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改 (配置改为调用方传入快照, 去掉调试统计)。
//

import Cocoa
import os

/// 一次滚动手势的配置快照: 主线程在 update 时传入, CVDisplayLink 线程只读
struct PosterConfig {
    /// 插值系数 (0-1), 由 Settings.durationTransition 生成, 越小惯性越长
    var transition: Double
    var speed: Double
    /// 加速键 (左 Option) 按下时为 5, 否则为 1
    var amplification: Double
    var simTrackpad: Bool
    /// 单帧输出与剩余距离低于该像素值时视为静止
    var deadZone: Double
    /// Chrome 需要一个 TrackingEnd 收尾帧, 否则会残留滚动状态
    var targetIsChrome: Bool
}

final class ScrollPoster {

    static let shared = ScrollPoster()
    private init() {}

    private let filter = ScrollFilter()
    private var poster: CVDisplayLink?
    private var current = (y: 0.0, x: 0.0) // 已派发的累计距离
    private var delta = (y: 0.0, x: 0.0)   // 上一次输入的方向
    private var buffer = (y: 0.0, x: 0.0)  // 目标累计距离
    private var shifting = false
    private var config = PosterConfig(
        transition: Settings.transition(for: Settings.defaultDuration),
        speed: Settings.defaultSpeed,
        amplification: 1.0,
        simTrackpad: false,
        deadZone: Settings.deadZone,
        targetIsChrome: false
    )

    // 滚轮事件间隔低于 continuation 视为持续跟随; 介于 continuation 与 separation 之间衔接惯性
    private let manualContinuationThreshold: CFTimeInterval = 0.18
    private let manualSeparationThreshold: CFTimeInterval = 0.45
    private let trackingEndAdvance: CFTimeInterval = 0.04
    private let momentumEndDelay: CFTimeInterval = 0.13
    private var lastManualEventTime: CFTimeInterval = 0.0
    private var manualInputEnded = true
    private var momentumActive = false
    private var momentumEndScheduledTime: CFTimeInterval?
    private var trackingEndScheduledTime: CFTimeInterval?

    // 保护上面所有滚动状态及 ScrollPhase; 主线程 (update/stop) 与 CVDisplayLink 线程 (processing) 并发访问
    private var stateLock = os_unfair_lock_s()
    private let dispatchContext = ScrollDispatchContext.shared

    // CVDisplayLink 守护: 回调超过 2s 没来视为僵尸 link 并重建
    private var keeper: Timer?
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0

    // 显示器唤醒/重连时会先短暂报告过渡刷新率 (如先 60Hz 再 144Hz), 若 link 恰好在此时建立,
    // 平滑滚动会一直按低帧率绘制; 建立后延迟复查几次, 标称率明显偏低就重建追平
    private var rateVerifyTimer: Timer?
    private var rateVerifyAttemptsLeft = 0
    private var isVerifying = false
    private let rateVerifyDelays: [TimeInterval] = [2.0, 4.0, 8.0]
    private let rateVerifyRatio = 0.7

    /// 仅主线程访问
    var isAvailable: Bool { poster != nil }
}

// MARK: - 滚动数据更新
extension ScrollPoster {

    @discardableResult
    func update(event: CGEvent, y: Double, x: Double, config newConfig: PosterConfig) -> ScrollPoster {
        guard dispatchContext.capture(event: event) else { return self }
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        config = newConfig
        let gain = newConfig.speed * newConfig.amplification
        // 同向滚动累加目标距离; 反向时丢弃未完成的惯性, 立即转向
        if y * delta.y > 0 {
            buffer.y += y * gain
        } else {
            buffer.y = y * gain
            current.y = 0.0
        }
        if x * delta.x > 0 {
            buffer.x += x * gain
        } else {
            buffer.x = x * gain
            current.x = 0.0
        }
        delta = (y: y, x: x)
        let now = CFAbsoluteTimeGetCurrent()
        let separatedByTime = lastManualEventTime <= 0.0 || now - lastManualEventTime >= manualSeparationThreshold
        let phase = ScrollPhase.shared.phase
        let separatedPhase = phase == .idle || phase == .leave || phase == .momentumEnd || phase == .trackingEnd
        let separated = manualInputEnded || separatedByTime || separatedPhase
        perform(ScrollPhase.shared.onManualInputDetected(isSeparated: separated), emitTargetImmediately: false)
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
        return self
    }

    func updateShifting(enable: Bool) {
        os_unfair_lock_lock(&stateLock)
        shifting = enable
        os_unfair_lock_unlock(&stateLock)
    }

    func reset() {
        dispatchContext.invalidateAll()
        os_unfair_lock_lock(&stateLock)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

    /// 调用方须持有 stateLock
    private func resetUnlocked() {
        dispatchContext.clearContext()
        current = (y: 0.0, x: 0.0)
        delta = (y: 0.0, x: 0.0)
        buffer = (y: 0.0, x: 0.0)
        filter.reset()
        ScrollPhase.shared.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }

    /// 按住转向键时把纵向滚动转成横向;
    /// MX Master 等鼠标按下 Shift 后自己就会发横向事件, 只有「仅纵向有值」时才交换
    private func shift(_ value: (y: Double, x: Double)) -> (y: Double, x: Double) {
        if shifting && value.y != 0.0 && value.x == 0.0 {
            return (y: value.x, x: value.y)
        }
        return value
    }
}

// MARK: - CVDisplayLink 生命周期
extension ScrollPoster {

    func create() {
        if let old = poster {
            if CVDisplayLinkIsRunning(old) { CVDisplayLinkStop(old) }
            poster = nil
        }
        var created: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&created)
        guard result == kCVReturnSuccess, let link = created else {
            NSLog("SmoothScroll: CVDisplayLink creation failed (%d)", result)
            return
        }
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, _ in
            ScrollPoster.shared.processing()
            return kCVReturnSuccess
        }, nil)
        poster = link
        // 复查内部触发的重建不重置复查序列
        if !isVerifying { scheduleRateVerify() }
    }

    func tryStart() {
        guard let link = poster else {
            if !recreateDisplayLink(start: true) {
                // 冷却期拒绝重建时清掉陈旧 buffer, 防止恢复后滚动跳变
                reset()
            }
            return
        }
        if !CVDisplayLinkIsRunning(link) {
            if CVDisplayLinkStart(link) == kCVReturnSuccess {
                // 给守护一个宽限期, 避免把刚启动的 link 误判为僵尸
                markCallback()
            } else {
                recreateDisplayLink(start: true)
            }
        }
    }

    func stop(_ requestedPhase: Phase = .momentumEnd) {
        if let link = poster { CVDisplayLinkStop(link) }
        // 让已排队的旧帧失效; 收尾帧使用新代次
        dispatchContext.advanceGeneration()
        os_unfair_lock_lock(&stateLock)
        let plan = requestedPhase == .momentumEnd
            ? ScrollPhase.shared.onMomentumFinish()
            : ScrollPhase.shared.onManualInputEnded()
        if config.simTrackpad {
            perform(plan, emitTargetImmediately: true)
        } else if config.targetIsChrome, let snapshot = dispatchContext.preparePostingSnapshot() {
            post(snapshot, (y: 0.0, x: 0.0), phaseOverride: Phase.trackingEnd.fieldValues, fallbackToCurrentPhase: false)
        }
        // 不递增 generation, 保留本次收尾帧的有效性
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

    /// 重建 CVDisplayLink (带冷却期); start 为 false 时只重建不启动, 避免空闲时 link 空转
    @discardableResult
    func recreateDisplayLink(start: Bool) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        create()
        if start, let link = poster {
            if CVDisplayLinkStart(link) == kCVReturnSuccess {
                markCallback()
            } else {
                NSLog("SmoothScroll: CVDisplayLink start failed after recreate")
            }
        }
        return true
    }

    /// 显示器配置变化后重建 link, 使其绑定到新的刷新率
    func handleScreenChange() {
        let wasRunning = poster.map { CVDisplayLinkIsRunning($0) } ?? false
        lastRecreateAttempt = 0
        recreateDisplayLink(start: wasRunning)
    }

    func startKeeper() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }

    func stopKeeper() {
        keeper?.invalidate()
        keeper = nil
        rateVerifyTimer?.invalidate()
        rateVerifyTimer = nil
        rateVerifyAttemptsLeft = 0
    }

    func destroy() {
        stop()
        stopKeeper()
        poster = nil
    }

    private func markCallback() {
        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&stateLock)
    }

    private func healthCheck() {
        guard let link = poster else {
            recreateDisplayLink(start: false)
            return
        }
        guard CVDisplayLinkIsRunning(link) else { return }
        os_unfair_lock_lock(&stateLock)
        let lastTime = lastCallbackTime
        os_unfair_lock_unlock(&stateLock)
        // lastTime > 0 避免首次回调前误判
        if lastTime > 0 && CFAbsoluteTimeGetCurrent() - lastTime > 2.0 {
            NSLog("SmoothScroll: zombie CVDisplayLink detected, recreating")
            recreateDisplayLink(start: true)
        }
    }

    private func scheduleRateVerify() {
        rateVerifyAttemptsLeft = rateVerifyDelays.count
        armNextRateVerify()
    }

    private func armNextRateVerify() {
        rateVerifyTimer?.invalidate()
        guard rateVerifyAttemptsLeft > 0 else {
            rateVerifyTimer = nil
            return
        }
        let delay = rateVerifyDelays[rateVerifyDelays.count - rateVerifyAttemptsLeft]
        rateVerifyTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.verifyRateAndFixIfNeeded()
        }
    }

    private func verifyRateAndFixIfNeeded() {
        rateVerifyAttemptsLeft -= 1
        guard let link = poster else {
            rateVerifyTimer = nil
            return
        }
        let nominal = Self.nominalHz(of: link)
        let maxHz = Self.maxActiveDisplayHz()
        guard nominal > 1, maxHz > 1, nominal < maxHz * rateVerifyRatio else {
            rateVerifyTimer = nil
            rateVerifyAttemptsLeft = 0
            return
        }
        NSLog("SmoothScroll: display link %.0fHz below display %.0fHz, recreating", nominal, maxHz)
        let wasRunning = CVDisplayLinkIsRunning(link)
        isVerifying = true
        create()
        isVerifying = false
        if wasRunning, let refreshed = poster {
            CVDisplayLinkStart(refreshed)
        }
        // 显示器仍在过渡: 清除冷却, 让后续屏幕变化能及时用最终配置重建
        lastRecreateAttempt = 0
        armNextRateVerify()
    }

    private static func nominalHz(of link: CVDisplayLink) -> Double {
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        guard period.timeValue != 0, period.timeScale != 0 else { return -1 }
        let seconds = Double(period.timeValue) / Double(period.timeScale)
        return seconds > 0 ? 1.0 / seconds : -1
    }

    private static func maxActiveDisplayHz() -> Double {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return -1 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return -1 }
        var maxHz = -1.0
        for id in ids.prefix(Int(count)) {
            if let hz = CGDisplayCopyDisplayMode(id)?.refreshRate, hz > maxHz { maxHz = hz }
        }
        return maxHz
    }
}

// MARK: - 插值与派发
extension ScrollPoster {

    /// CVDisplayLink 线程每帧调用
    fileprivate func processing() {
        var pendingStopPhase: Phase?
        os_unfair_lock_lock(&stateLock)
        let now = CFAbsoluteTimeGetCurrent()
        lastCallbackTime = now
        // 每帧走完剩余距离的固定比例 (指数逼近), 形成先快后慢的惯性曲线
        let frame = (
            y: (buffer.y - current.y) * config.transition,
            x: (buffer.x - current.x) * config.transition
        )
        current = (y: current.y + frame.y, x: current.x + frame.x)
        let output = shift(filter.fill(with: frame))

        // 超过持续跟随阈值没有新输入, 结束手动阶段
        if !manualInputEnded && lastManualEventTime > 0.0 && now - lastManualEventTime > manualContinuationThreshold {
            let endPlan = ScrollPhase.shared.onManualInputEnded()
            if !endPlan.isEmpty {
                perform(endPlan, emitTargetImmediately: true)
            }
            manualInputEnded = true
            if trackingEndScheduledTime == nil {
                trackingEndScheduledTime = now + trackingEndAdvance
            }
        }

        let residual = max((buffer.y - current.y).magnitude, (buffer.x - current.x).magnitude)
        let deadZone = config.deadZone
        if manualInputEnded && residual > deadZone {
            let plan = momentumActive ? ScrollPhase.shared.onMomentumOngoing() : ScrollPhase.shared.onMomentumStart()
            perform(plan, emitTargetImmediately: false)
            momentumActive = true
            momentumEndScheduledTime = nil
            trackingEndScheduledTime = nil
        } else if momentumActive && residual <= deadZone {
            if momentumEndScheduledTime == nil {
                momentumEndScheduledTime = now + momentumEndDelay
            }
        } else {
            momentumEndScheduledTime = nil
            momentumActive = false
        }

        let outputMagnitude = max(output.y.magnitude, output.x.magnitude)
        if outputMagnitude > deadZone {
            post(output)
        }

        if let scheduled = momentumEndScheduledTime, momentumActive, now >= scheduled {
            momentumEndScheduledTime = nil
            momentumActive = false
            pendingStopPhase = .momentumEnd
        }
        if pendingStopPhase == nil && manualInputEnded && !momentumActive && residual <= deadZone {
            if let scheduled = trackingEndScheduledTime, now >= scheduled, outputMagnitude <= deadZone {
                trackingEndScheduledTime = nil
                pendingStopPhase = .trackingEnd
            }
        } else {
            trackingEndScheduledTime = nil
        }
        os_unfair_lock_unlock(&stateLock)
        if let phase = pendingStopPhase {
            stop(phase)
        }
    }

    /// 调用方须持有 stateLock
    private func perform(_ plan: ScrollPhase.TransitionPlan, emitTargetImmediately: Bool) {
        guard !plan.isEmpty else { return }
        for item in plan.queue {
            emitPhase(item)
        }
        if let target = plan.target {
            if emitTargetImmediately {
                emitPhase(target)
            } else {
                ScrollPhase.shared.apply(phase: target.0, autoAdvance: target.1)
            }
        }
    }

    private func emitPhase(_ item: (Phase, Phase?)) {
        ScrollPhase.shared.apply(phase: item.0, autoAdvance: item.1)
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            ScrollPhase.shared.didDeliverFrame()
            return
        }
        let phaseOverride = config.simTrackpad ? item.0.fieldValues : nil
        post(snapshot, (y: 0.0, x: 0.0), phaseOverride: phaseOverride, fallbackToCurrentPhase: false)
    }

    private func post(_ value: (y: Double, x: Double)) {
        guard let snapshot = dispatchContext.preparePostingSnapshot() else { return }
        post(snapshot, value, phaseOverride: nil, fallbackToCurrentPhase: true)
    }

    private func post(
        _ snapshot: ScrollDispatchContext.PostingSnapshot,
        _ value: (y: Double, x: Double),
        phaseOverride: (scroll: Double, momentum: Double)?,
        fallbackToCurrentPhase: Bool
    ) {
        let event = snapshot.event
        var phases = phaseOverride
        if phases == nil && fallbackToCurrentPhase && config.simTrackpad {
            phases = ScrollPhase.shared.phase.fieldValues
        }
        if let phases {
            event.setDoubleValueField(.scrollWheelEventScrollPhase, value: phases.scroll)
            event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: phases.momentum)
        }
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: value.y)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: value.x)
        // 标记为连续 (像素级) 滚动, 应用才会按 point delta 平滑渲染
        event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        ScrollUtils.markSyntheticSmoothEvent(event)
        dispatchContext.enqueue(snapshot)
        ScrollPhase.shared.didDeliverFrame()
    }
}
