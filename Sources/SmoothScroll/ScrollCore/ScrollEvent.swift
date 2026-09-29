//
// ScrollEvent.swift
// SmoothScroll
// 滚动事件轴数据解析。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollEvent.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改。
//

import Cocoa

struct AxisData {
    var scrollFix: Int64 = 0
    var scrollPt = 0.0
    var scrollFixPt = 0.0
    var valid = false
    var usableValue = 0.0
}

struct ScrollEvent {

    let event: CGEvent
    var y: AxisData
    var x: AxisData

    init(with event: CGEvent) {
        self.event = event
        y = Self.axis(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
        x = Self.axis(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
    }

    /// 触控板 / Magic Mouse 带 phase 或累计加速度; 黑苹果触控板驱动直接模拟鼠标输入, 无法区分
    var isTrackpad: Bool {
        let looksLikeTrackpad = event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0.0
            || event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0.0
            || event.getDoubleValueField(.scrollWheelEventScrollCount) != 0.0
        guard looksLikeTrackpad else { return false }
        // Logitech Options 会给鼠标滚轮事件补上 phase, 需要按事件来源排除
        let logiPID = ScrollUtils.shared.logitechOptionsPID()
        if logiPID != 0 && pid_t(event.getIntegerValueField(.eventSourceUnixProcessID)) == logiPID {
            return false
        }
        return true
    }

    // 优先使用像素值; 只有行值时 usableValue 可能很小, 由调用方按 step 归一化
    private static func axis(_ event: CGEvent, _ fix: CGEventField, _ pt: CGEventField, _ fixPt: CGEventField) -> AxisData {
        var data = AxisData()
        data.scrollFix = event.getIntegerValueField(fix)
        data.scrollPt = event.getDoubleValueField(pt)
        data.scrollFixPt = event.getDoubleValueField(fixPt)
        if data.scrollPt != 0.0 {
            data.valid = true
            data.usableValue = data.scrollPt
        } else if data.scrollFixPt != 0.0 {
            data.valid = true
            data.usableValue = data.scrollFixPt
        } else if data.scrollFix != 0 {
            data.valid = true
            data.usableValue = Double(data.scrollFix)
        }
        return data
    }

    mutating func reverseY() {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -y.scrollFix)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -y.scrollPt)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -y.scrollFixPt)
        y.usableValue = -y.usableValue
    }

    mutating func reverseX() {
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -x.scrollFix)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -x.scrollPt)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -x.scrollFixPt)
        x.usableValue = -x.usableValue
    }

    /// 单格滚轮位移不足 step 时抬升到 step, 保证每一格都有可感知的滚动距离
    static func normalized(_ value: Double, step: Double) -> Double {
        let magnitude = max(value.magnitude, step)
        return value > 0.0 ? magnitude : -magnitude
    }
}
