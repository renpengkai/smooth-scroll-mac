//
// StatusMenu.swift
// SmoothScroll
// 菜单栏图标与菜单, 是本应用唯一的界面。
//

import Cocoa
import ServiceManagement

final class StatusMenu: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let settings = Settings.shared

    private let smoothItem = NSMenuItem(title: "平滑滚动", action: nil, keyEquivalent: "")
    private let reverseItem = NSMenuItem(title: "反转鼠标滚动方向", action: nil, keyEquivalent: "")
    private let simTrackpadItem = NSMenuItem(title: "模拟触控板", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "登录时启动", action: nil, keyEquivalent: "")
    private var stepView: SliderMenuView!
    private var speedView: SliderMenuView!
    private var durationView: SliderMenuView!

    override init() {
        super.init()
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "SmoothScroll") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "S"
            }
        }
        buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu() {
        for (item, action) in [
            (smoothItem, #selector(toggleSmooth)),
            (reverseItem, #selector(toggleReverse)),
            (simTrackpadItem, #selector(toggleSimTrackpad)),
        ] {
            item.target = self
            item.action = action
            menu.addItem(item)
        }
        menu.addItem(.separator())

        stepView = SliderMenuView(title: "最小步长", range: Settings.stepRange, value: settings.step, format: "%.1f") { [weak self] in
            self?.settings.step = $0
        }
        speedView = SliderMenuView(title: "速度增益", range: Settings.speedRange, value: settings.speed, format: "%.2f") { [weak self] in
            self?.settings.speed = $0
        }
        durationView = SliderMenuView(title: "惯性时长", range: Settings.durationRange, value: settings.duration, format: "%.2f") { [weak self] in
            self?.settings.duration = $0
        }
        for view in [stepView!, speedView!, durationView!] {
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }
        addItem("恢复默认参数", #selector(resetParameters))
        menu.addItem(.separator())

        permissionItem.target = self
        permissionItem.action = #selector(openAccessibilitySettings)
        menu.addItem(permissionItem)
        loginItem.target = self
        loginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(loginItem)
        menu.addItem(.separator())

        addItem("平滑算法来自 Mos (CC BY-NC 4.0)", #selector(openMos))
        addItem("退出 SmoothScroll", #selector(quit), key: "q")
        refresh()
    }

    private func addItem(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func refresh() {
        smoothItem.state = settings.smooth ? .on : .off
        reverseItem.state = settings.reverse ? .on : .off
        simTrackpadItem.state = settings.simTrackpad ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let trusted = AXIsProcessTrusted()
        permissionItem.title = trusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权（点此前往设置）"
        permissionItem.isEnabled = !trusted
        statusItem.button?.appearsDisabled = !(trusted && settings.smooth)
    }

    @objc private func toggleSmooth() {
        settings.smooth.toggle()
        refresh()
    }

    @objc private func toggleReverse() {
        settings.reverse.toggle()
        refresh()
    }

    @objc private func toggleSimTrackpad() {
        settings.simTrackpad.toggle()
        refresh()
    }

    @objc private func resetParameters() {
        settings.resetScrollParameters()
        stepView.setValue(settings.step)
        speedView.setValue(settings.speed)
        durationView.setValue(settings.duration)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // 常见原因: App 不在「应用程序」目录, 或被 App Translocation 从隔离路径运行
            let alert = NSAlert()
            alert.messageText = "无法修改登录启动"
            alert.informativeText = "请先把 SmoothScroll.app 移到「应用程序」文件夹再试。\n\(error.localizedDescription)"
            alert.runModal()
        }
        refresh()
    }

    @objc private func openMos() {
        if let url = URL(string: "https://github.com/Caldis/Mos") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
