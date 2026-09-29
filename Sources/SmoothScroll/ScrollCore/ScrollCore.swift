//
// ScrollCore.swift
// SmoothScroll
// 滚动事件截取入口。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollCore.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改 (去掉按应用配置与自定义热键, 热键固定为 Mos 默认值)。
//

import Cocoa

final class ScrollCore {

    static let shared = ScrollCore()
    private init() {}

    private(set) var isActive = false

    // 与 Mos 默认热键一致, 只认左侧修饰键
    private static let dashKeyCode: Int64 = 58   // 左 Option: 5 倍加速
    private static let toggleKeyCode: Int64 = 56 // 左 Shift: 纵向转横向
    private static let blockKeyCode: Int64 = 55  // 左 Command: 临时关闭平滑 (保留 Cmd+滚轮缩放)

    fileprivate var dashAmplification = 1.0
    fileprivate var toggleScroll = false {
        didSet { ScrollPoster.shared.updateShifting(enable: toggleScroll) }
    }
    fileprivate var blockSmooth = false

    private var scrollInterceptor: Interceptor?
    private var hotkeyInterceptor: Interceptor?
    private var mouseInterceptor: Interceptor?

    /// 需要辅助功能权限; 未授权时返回 false
    @discardableResult
    func enable() -> Bool {
        if isActive { return true }
        do {
            let scroll = try Interceptor(
                mask: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                handler: scrollCallback,
                options: .defaultTap
            )
            scroll.onRestart = { ScrollPoster.shared.stop(.trackingEnd) }
            scrollInterceptor = scroll
            hotkeyInterceptor = try Interceptor(
                mask: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
                handler: hotkeyCallback,
                options: .listenOnly
            )
            mouseInterceptor = try Interceptor(
                mask: CGEventMask(1 << CGEventType.leftMouseDown.rawValue),
                handler: mouseCallback,
                options: .listenOnly
            )
        } catch {
            NSLog("SmoothScroll: create interceptor failed: %@", String(describing: error))
            releaseInterceptors()
            return false
        }
        ScrollPoster.shared.create()
        ScrollPoster.shared.startKeeper()
        isActive = true
        return true
    }

    func disable() {
        guard isActive else { return }
        isActive = false
        ScrollPoster.shared.destroy()
        releaseInterceptors()
        dashAmplification = 1.0
        toggleScroll = false
        blockSmooth = false
    }

    private func releaseInterceptors() {
        scrollInterceptor?.stop()
        hotkeyInterceptor?.stop()
        mouseInterceptor?.stop()
        scrollInterceptor = nil
        hotkeyInterceptor = nil
        mouseInterceptor = nil
    }

    fileprivate static func handleFlagsChanged(_ event: CGEvent) {
        let core = ScrollCore.shared
        let flags = event.flags
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case dashKeyCode: core.dashAmplification = flags.contains(.maskAlternate) ? 5.0 : 1.0
        case toggleKeyCode: core.toggleScroll = flags.contains(.maskShift)
        case blockKeyCode: core.blockSmooth = flags.contains(.maskCommand)
        default: break
        }
    }
}

// MARK: - Event tap 回调 (C 函数指针, 不能捕获上下文, 统一走单例)

private let scrollCallback: CGEventTapCallBack = { _, type, event, _ in
    let passthrough = Unmanaged.passUnretained(event)
    // tap 被系统超时禁用时清理 poster; 重新启用交给 Interceptor 的守护定时器 (带防自锁冷却)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        ScrollPoster.shared.stop(.trackingEnd)
        return passthrough
    }
    guard type == .scrollWheel else { return passthrough }
    // 自己合成的平滑事件不能再进平滑管线
    if ScrollUtils.isSyntheticSmoothEvent(event) { return passthrough }

    var scrollEvent = ScrollEvent(with: event)
    // Magic Mouse 的滚动特征与触控板一致, 同样不处理
    if scrollEvent.isTrackpad { return passthrough }
    if ScrollUtils.shared.isRemoteSmoothedEvent(event) { return passthrough }

    let settings = Settings.shared
    let core = ScrollCore.shared
    let hasVertical = scrollEvent.y.valid && scrollEvent.y.usableValue != 0.0
    let hasHorizontal = scrollEvent.x.valid && scrollEvent.x.usableValue != 0.0

    // 方向翻转先于平滑, 这样按住 Command 关闭平滑时方向依然一致
    if settings.reverse {
        if hasVertical { scrollEvent.reverseY() }
        if hasHorizontal { scrollEvent.reverseX() }
    }

    let targetApplication = ScrollUtils.shared.runningApplication(from: event)
    guard settings.smooth,
          !core.blockSmooth,
          !ScrollUtils.shared.isLaunchpadActive(targetApplication) else {
        return passthrough
    }

    let step = settings.step
    let y = hasVertical ? ScrollEvent.normalized(scrollEvent.y.usableValue, step: step) : 0.0
    let x = hasHorizontal ? ScrollEvent.normalized(scrollEvent.x.usableValue, step: step) : 0.0
    guard y != 0.0 || x != 0.0 else { return passthrough }

    let config = PosterConfig(
        transition: settings.durationTransition,
        speed: settings.speed,
        amplification: core.dashAmplification,
        simTrackpad: settings.simTrackpad,
        deadZone: Settings.deadZone,
        targetIsChrome: targetApplication?.bundleIdentifier == "com.google.Chrome"
    )
    ScrollPoster.shared.update(event: event, y: y, x: x, config: config).tryStart()
    // CVDisplayLink 不可用时放行原事件, 宁可不平滑也不能吞掉滚动
    return ScrollPoster.shared.isAvailable ? nil : passthrough
}

private let hotkeyCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .flagsChanged {
        ScrollCore.handleFlagsChanged(event)
    }
    return Unmanaged.passUnretained(event)
}

// 点击左键立即刹停惯性, 与触控板点按停止的手感一致
private let mouseCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .leftMouseDown {
        ScrollPoster.shared.stop()
    }
    return Unmanaged.passUnretained(event)
}
