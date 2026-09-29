//
// AppDelegate.swift
// SmoothScroll
// 启动、辅助功能授权与系统事件 (休眠唤醒、显示器变化) 处理。
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusMenu: StatusMenu?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu()
        startWhenTrusted(prompt: true)

        // 休眠唤醒后 event tap 与 display link 都可能失效, 整体重建最稳妥
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            ScrollCore.shared.disable()
            self?.startWhenTrusted(prompt: false)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            ScrollPoster.shared.handleScreenChange()
        }
        NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionLost, object: nil, queue: .main
        ) { [weak self] _ in
            ScrollCore.shared.disable()
            self?.statusMenu?.refresh()
            self?.startWhenTrusted(prompt: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScrollCore.shared.disable()
    }

    /// 已授权则立即启动; 否则 (可选) 弹出系统授权提示, 并轮询直到用户在系统设置里勾选
    private func startWhenTrusted(prompt: Bool) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if AXIsProcessTrusted() {
            ScrollCore.shared.enable()
            statusMenu?.refresh()
            return
        }
        if prompt {
            // 即 kAXTrustedCheckOptionPrompt; 直接用字面量, 避免不同 SDK 下 Unmanaged 导入方式不一致
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        statusMenu?.refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            ScrollCore.shared.enable()
            self?.statusMenu?.refresh()
        }
    }
}
