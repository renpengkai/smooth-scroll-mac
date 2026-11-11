//
// ButtonAction.swift
// SmoothScroll
// 鼠标按键可绑定的动作, 以及动作的执行 (合成键盘事件 / 调起调度中心)。
//

import Cocoa

struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    /// CGEventFlags 中的修饰键部分
    var flags: UInt64
    var display: String

    init(event: NSEvent) {
        let modifiers = event.modifierFlags
        var flags = CGEventFlags()
        var text = ""
        if modifiers.contains(.control) { flags.insert(.maskControl); text += "⌃" }
        if modifiers.contains(.option) { flags.insert(.maskAlternate); text += "⌥" }
        if modifiers.contains(.shift) { flags.insert(.maskShift); text += "⇧" }
        if modifiers.contains(.command) { flags.insert(.maskCommand); text += "⌘" }
        keyCode = event.keyCode
        self.flags = flags.rawValue
        display = text + Self.keyName(event)
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        if let name = specialKeyNames[event.keyCode] { return name }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? "键 \(event.keyCode)" : chars.uppercased()
    }
}

enum ButtonAction: Codable, Equatable {
    case back
    case forward
    case missionControl
    case appWindows
    case showDesktop
    case spaceLeft
    case spaceRight
    case shortcut(KeyShortcut)

    static let presets: [ButtonAction] = [
        .back, .forward, .missionControl, .appWindows, .showDesktop, .spaceLeft, .spaceRight,
    ]

    var title: String {
        switch self {
        case .back: return "后退（⌘[）"
        case .forward: return "前进（⌘]）"
        case .missionControl: return "调度中心"
        case .appWindows: return "应用程序窗口"
        case .showDesktop: return "显示桌面"
        case .spaceLeft: return "切换到左侧桌面"
        case .spaceRight: return "切换到右侧桌面"
        case .shortcut(let shortcut): return "快捷键 \(shortcut.display)"
        }
    }

    func perform() {
        switch self {
        case .back: KeyPoster.post(33, .maskCommand)
        case .forward: KeyPoster.post(30, .maskCommand)
        case .missionControl: Self.openMissionControl()
        case .appWindows: Self.openMissionControl("2")
        case .showDesktop: Self.openMissionControl("1")
        case .spaceLeft: KeyPoster.post(123, .maskControl)
        case .spaceRight: KeyPoster.post(124, .maskControl)
        case .shortcut(let shortcut): KeyPoster.post(shortcut.keyCode, CGEventFlags(rawValue: shortcut.flags))
        }
    }

    /// 调度中心 App 的参数: 无参数为调度中心, 1 为显示桌面, 2 为当前应用的所有窗口
    private static func openMissionControl(_ argument: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        process.arguments = argument.map { [$0] } ?? []
        do {
            try process.run()
        } catch {
            NSLog("SmoothScroll: launch Mission Control failed: %@", String(describing: error))
        }
    }
}

enum KeyPoster {
    private static let arrowKeys: Set<UInt16> = [123, 124, 125, 126]
    private static let navigationKeys: Set<UInt16> = [115, 116, 117, 119, 121]

    static func post(_ keyCode: UInt16, _ flags: CGEventFlags) {
        var flags = flags
        // 与真实键盘一致: 方向键带 fn + 小键盘标记, 否则「⌃← 切换桌面」等系统快捷键不响应
        if arrowKeys.contains(keyCode) {
            flags.formUnion([.maskSecondaryFn, .maskNumericPad])
        } else if navigationKeys.contains(keyCode) {
            flags.insert(.maskSecondaryFn)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
