//
// ButtonMenu.swift
// SmoothScroll
// 「自定义鼠标按键」子菜单: 为每个按键选择动作、录制快捷键、添加其他按键。
//

import Cocoa

final class ButtonMenu: NSObject, NSMenuDelegate {

    let menu = NSMenu()
    private let settings = Settings.shared

    /// CGEvent 按键编号: 2 中键, 3/4 为常见的后退/前进侧键
    private static let fixedButtons = [2, 3, 4]

    private final class Choice: NSObject {
        let button: Int
        let action: ButtonAction?
        init(button: Int, action: ButtonAction?) {
            self.button = button
            self.action = action
        }
    }

    override init() {
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    static func name(of button: Int) -> String {
        switch button {
        case 2: return "中键"
        case 3: return "侧键（后退）"
        case 4: return "侧键（前进）"
        default: return "按键 \(button + 1)"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for button in Self.fixedButtons + settings.extraButtons.sorted() {
            let current = settings.buttonBindings[button]?.title ?? "默认"
            let item = NSMenuItem(title: "\(Self.name(of: button))：\(current)", action: nil, keyEquivalent: "")
            item.submenu = actionMenu(for: button)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem(to: menu, "添加其他按键…", #selector(addButton), choice: nil)
        let resetItem = addItem(to: menu, "全部恢复默认", #selector(resetAll), choice: nil)
        resetItem.isEnabled = !settings.buttonBindings.isEmpty || !settings.extraButtons.isEmpty
    }

    private func actionMenu(for button: Int) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = settings.buttonBindings[button]

        addItem(to: submenu, "默认（系统行为）", #selector(choose(_:)), choice: Choice(button: button, action: nil))
            .state = current == nil ? .on : .off
        submenu.addItem(.separator())
        for preset in ButtonAction.presets {
            addItem(to: submenu, preset.title, #selector(choose(_:)), choice: Choice(button: button, action: preset))
                .state = current == preset ? .on : .off
        }
        submenu.addItem(.separator())
        let custom = addItem(to: submenu, "自定义快捷键…", #selector(recordShortcut(_:)), choice: Choice(button: button, action: nil))
        if case .shortcut(let shortcut) = current {
            custom.title = "自定义快捷键：\(shortcut.display)…"
            custom.state = .on
        }
        if settings.extraButtons.contains(button) {
            submenu.addItem(.separator())
            addItem(to: submenu, "移除此按键", #selector(removeButton(_:)), choice: Choice(button: button, action: nil))
        }
        return submenu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, choice: Choice?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = choice
        menu.addItem(item)
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice else { return }
        settings.buttonBindings[choice.button] = choice.action
    }

    @objc private func recordShortcut(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice,
              let shortcut = Self.runShortcutRecorder(for: choice.button) else { return }
        settings.buttonBindings[choice.button] = .shortcut(shortcut)
    }

    @objc private func removeButton(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice else { return }
        settings.buttonBindings[choice.button] = nil
        settings.extraButtons.removeAll { $0 == choice.button }
    }

    @objc private func resetAll() {
        settings.buttonBindings = [:]
        settings.extraButtons = []
    }

    @objc private func addButton() {
        let alert = NSAlert()
        alert.messageText = "添加鼠标按键"
        alert.informativeText = "请按下鼠标上要自定义的按键（左键、右键除外）。"
        alert.addButton(withTitle: "取消")
        var captured: Int?
        ButtonCore.shared.onCapture = { button in
            captured = button
            NSApp.abortModal()
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        ButtonCore.shared.onCapture = nil

        guard let button = captured else { return }
        if !Self.fixedButtons.contains(button), !settings.extraButtons.contains(button) {
            settings.extraButtons.append(button)
        }
        let done = NSAlert()
        done.messageText = "已识别：\(Self.name(of: button))"
        done.informativeText = "在「自定义鼠标按键」菜单中为它选择动作。"
        done.runModal()
    }

    /// 录制期间吞掉所有按键 (包括回车、Esc), 只能用鼠标点按钮确认或取消
    private static func runShortcutRecorder(for button: Int) -> KeyShortcut? {
        let alert = NSAlert()
        alert.messageText = "为「\(name(of: button))」录制快捷键"
        alert.informativeText = "按下要触发的组合键（例如 ⌘W），然后点「确定」。"
        let label = NSTextField(labelWithString: "等待按键…")
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 240, height: 28)
        alert.accessoryView = label
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let okButton = alert.buttons[0]
        okButton.isEnabled = false

        var recorded: KeyShortcut?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let shortcut = KeyShortcut(event: event)
            recorded = shortcut
            label.stringValue = shortcut.display
            okButton.isEnabled = true
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        return response == .alertFirstButtonReturn ? recorded : nil
    }
}
