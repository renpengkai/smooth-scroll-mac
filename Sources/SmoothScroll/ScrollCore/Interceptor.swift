//
// Interceptor.swift
// SmoothScroll
// CGEventTap 封装。改编自 Mos (https://github.com/Caldis/Mos) Utils/Interceptor.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改。
//

import Cocoa

final class Interceptor {

    enum InterceptorError: Error {
        case eventTapCreationFailed
        case eventTapEnableFailed
    }

    // 防自锁: 主线程被阻塞时 active tap 无响应, 系统超时禁用 tap 后输入才恢复;
    // keeper 若盲目重启会把刚恢复的输入再次冻住, 所以窗口期内重启达到上限即进入冷却
    static let autoRestartWindow: TimeInterval = 60
    static let autoRestartLimit = 3

    private let tap: CFMachPort
    private let source: CFRunLoopSource
    private var keeper: Timer?
    private var autoRestartHistory: [Date] = []

    /// 重启时的额外清理 (闭包不应捕获 Interceptor 自身, 否则形成循环引用)
    var onRestart: (() -> Void)?

    init(mask: CGEventMask, handler: @escaping CGEventTapCallBack, options: CGEventTapOptions) throws {
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: handler,
            userInfo: nil
        ) else {
            throw InterceptorError.eventTapCreationFailed
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw InterceptorError.eventTapCreationFailed
        }
        self.tap = tap
        self.source = source
        try start()
    }

    deinit {
        stop()
        // 只释放引用不会销毁 tap, 不 invalidate 的话 WindowServer 会一直保留这个注册
        CFMachPortInvalidate(tap)
    }

    var isRunning: Bool { CGEvent.tapIsEnabled(tap: tap) }

    func start() throws {
        // 权限已被撤销时不启用 tap, 避免僵尸 tap 吞掉系统事件
        guard AXIsProcessTrusted() else {
            throw InterceptorError.eventTapEnableFailed
        }
        if !CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }

    func stop() {
        keeper?.invalidate()
        keeper = nil
        CGEvent.tapEnable(tap: tap, enable: false)
        if CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func healthCheck() {
        guard AXIsProcessTrusted() else {
            stop()
            onRestart?()
            NotificationCenter.default.post(name: .accessibilityPermissionLost, object: nil)
            return
        }
        guard !isRunning else { return }
        let now = Date()
        autoRestartHistory.removeAll { now.timeIntervalSince($0) >= Self.autoRestartWindow }
        guard autoRestartHistory.count < Self.autoRestartLimit else {
            NSLog("SmoothScroll: event tap auto-restart throttled, cooling down")
            return
        }
        autoRestartHistory.append(now)
        restart()
    }

    private func restart() {
        keeper?.invalidate()
        keeper = nil
        CGEvent.tapEnable(tap: tap, enable: false)
        onRestart?()
        keeper = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            try? self?.start()
        }
    }
}

extension Notification.Name {
    /// 辅助功能权限在运行时被撤销
    static let accessibilityPermissionLost = Notification.Name("SmoothScrollAccessibilityPermissionLost")
}
