//
// Settings.swift
// SmoothScroll
// 用户设置 (UserDefaults)。默认值与 Mos 一致。
//

import Foundation

/// 仅主线程读写; CVDisplayLink 线程通过 PosterConfig 快照读取
final class Settings {

    static let shared = Settings()

    static let defaultStep = 33.6
    static let defaultSpeed = 2.70
    static let defaultDuration = 4.35
    static let deadZone = 1.0

    static let stepRange = 1.0...100.0
    static let speedRange = 1.0...10.0
    static let durationRange = 1.0...5.0

    private enum Key {
        static let smooth = "smooth"
        static let step = "step"
        static let speed = "speed"
        static let duration = "duration"
        static let showInMenuBar = "showInMenuBar"
        static let buttonBindings = "buttonBindings"
        static let extraButtons = "extraButtons"
    }

    var smooth: Bool {
        didSet { UserDefaults.standard.set(smooth, forKey: Key.smooth) }
    }
    /// 单格滚轮的最小像素位移
    var step: Double {
        didSet { UserDefaults.standard.set(step, forKey: Key.step) }
    }
    /// 位移增益
    var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: Key.speed) }
    }
    /// 惯性持续时间 (界面刻度, 1-5), 越大越顺滑拖尾越长
    var duration: Double {
        didSet {
            UserDefaults.standard.set(duration, forKey: Key.duration)
            durationTransition = Self.transition(for: duration)
        }
    }
    /// 是否在菜单栏显示图标; 关闭后平滑滚动仍后台运行, 并临时显示 Dock 图标以便再次打开
    var showInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: Key.showInMenuBar) }
    }
    /// 鼠标按键 (CGEvent 按键编号, 中键为 2) 到动作的映射; 不在表中的按键保持系统默认行为
    var buttonBindings: [Int: ButtonAction] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(buttonBindings), forKey: Key.buttonBindings) }
    }
    /// 通过「添加其他按键」录入的按键编号 (中键与两个侧键固定显示, 不在此列)
    var extraButtons: [Int] {
        didSet { UserDefaults.standard.set(extraButtons, forKey: Key.extraButtons) }
    }
    /// 由 duration 换算出的每帧插值系数
    private(set) var durationTransition: Double

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.smooth: true,
            Key.step: Self.defaultStep,
            Key.speed: Self.defaultSpeed,
            Key.duration: Self.defaultDuration,
            Key.showInMenuBar: true,
        ])
        smooth = defaults.bool(forKey: Key.smooth)
        step = defaults.double(forKey: Key.step)
        speed = defaults.double(forKey: Key.speed)
        duration = defaults.double(forKey: Key.duration)
        durationTransition = Self.transition(for: defaults.double(forKey: Key.duration))
        showInMenuBar = defaults.bool(forKey: Key.showInMenuBar)
        buttonBindings = defaults.data(forKey: Key.buttonBindings)
            .flatMap { try? JSONDecoder().decode([Int: ButtonAction].self, from: $0) } ?? [:]
        extraButtons = defaults.array(forKey: Key.extraButtons) as? [Int] ?? []
    }

    func resetScrollParameters() {
        step = Self.defaultStep
        speed = Self.defaultSpeed
        duration = Self.defaultDuration
    }

    /// Mos 的换算: y = 1 - sqrt(x / 5.2), 上界多加 0.2 保证结果不为 0 (否则永远滚不到终点); 保留三位小数
    static func transition(for duration: Double) -> Double {
        let upperLimit = durationRange.upperBound + 0.2
        let value = 1 - (duration / upperLimit).squareRoot()
        return (1000 * value).rounded() / 1000
    }
}
