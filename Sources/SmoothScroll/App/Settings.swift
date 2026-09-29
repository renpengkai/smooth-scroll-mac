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
        static let reverse = "reverse"
        static let simTrackpad = "simTrackpad"
        static let step = "step"
        static let speed = "speed"
        static let duration = "duration"
    }

    var smooth: Bool {
        didSet { UserDefaults.standard.set(smooth, forKey: Key.smooth) }
    }
    /// 翻转鼠标滚轮方向 (系统「自然滚动」同时作用于触控板和鼠标, Mos 默认对鼠标翻回来)
    var reverse: Bool {
        didSet { UserDefaults.standard.set(reverse, forKey: Key.reverse) }
    }
    /// 给合成事件附带触控板 phase, 让支持手势的应用 (如回弹、历史滑动) 当作触控板处理
    var simTrackpad: Bool {
        didSet { UserDefaults.standard.set(simTrackpad, forKey: Key.simTrackpad) }
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
    /// 由 duration 换算出的每帧插值系数
    private(set) var durationTransition: Double

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.smooth: true,
            Key.reverse: true,
            Key.simTrackpad: false,
            Key.step: Self.defaultStep,
            Key.speed: Self.defaultSpeed,
            Key.duration: Self.defaultDuration,
        ])
        smooth = defaults.bool(forKey: Key.smooth)
        reverse = defaults.bool(forKey: Key.reverse)
        simTrackpad = defaults.bool(forKey: Key.simTrackpad)
        step = defaults.double(forKey: Key.step)
        speed = defaults.double(forKey: Key.speed)
        duration = defaults.double(forKey: Key.duration)
        durationTransition = Self.transition(for: defaults.double(forKey: Key.duration))
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
