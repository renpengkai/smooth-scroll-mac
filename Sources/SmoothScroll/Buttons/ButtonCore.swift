//
// ButtonCore.swift
// SmoothScroll
// 截取鼠标左右键以外的按键 (中键、侧键等), 按用户绑定执行动作。未绑定的按键原样放行。
//

import Cocoa

final class ButtonCore {

    static let shared = ButtonCore()
    private init() {}

    private var interceptor: Interceptor?
    /// 被吞掉按下事件的按键; 对应的拖动与抬起也要一起吞掉, 否则应用会收到不成对的事件
    fileprivate var swallowed = Set<Int>()

    /// 非空时下一次按键只用于识别按键编号 (「添加其他按键」), 不执行任何动作
    var onCapture: ((Int) -> Void)?

    /// 需要辅助功能权限; 未授权时返回 false
    @discardableResult
    func enable() -> Bool {
        if interceptor != nil { return true }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        do {
            let interceptor = try Interceptor(mask: mask, handler: buttonCallback, options: .defaultTap)
            interceptor.onRestart = { ButtonCore.shared.swallowed.removeAll() }
            self.interceptor = interceptor
        } catch {
            NSLog("SmoothScroll: create button interceptor failed: %@", String(describing: error))
            return false
        }
        return true
    }

    func disable() {
        interceptor?.stop()
        interceptor = nil
        swallowed.removeAll()
    }

    /// 返回 true 表示吞掉该事件
    fileprivate func handle(_ type: CGEventType, button: Int) -> Bool {
        switch type {
        case .otherMouseDown:
            if let capture = onCapture {
                onCapture = nil
                swallowed.insert(button)
                DispatchQueue.main.async { capture(button) }
                return true
            }
            guard let action = Settings.shared.buttonBindings[button] else { return false }
            swallowed.insert(button)
            // 异步执行, 避免启动进程等耗时操作拖慢 tap 回调
            DispatchQueue.main.async { action.perform() }
            return true
        case .otherMouseUp:
            return swallowed.remove(button) != nil
        default:
            return swallowed.contains(button)
        }
    }
}

private let buttonCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        return ButtonCore.shared.handle(type, button: button) ? nil : Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
