//
// ScrollFilter.swift
// SmoothScroll
// 曲线峰值滤波, 去除滚动起始抖动。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollFilter.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改。
//

import Foundation

final class ScrollFilter {

    // Mos 每帧生成 [first, first+0.23d, first+0.5d, first+0.77d, next] 五点窗口, 但只读取下标 0 和 1;
    // 这里只保留这两位, 输出与原实现逐帧一致, 且热路径不再分配数组
    private var windowY = (0.0, 0.0)
    private var windowX = (0.0, 0.0)

    func fill(with next: (y: Double, x: Double)) -> (y: Double, x: Double) {
        windowY = Self.polish(windowY, with: next.y)
        windowX = Self.polish(windowX, with: next.x)
        return (y: windowY.0, x: windowX.0)
    }

    func reset() {
        windowY = (0.0, 0.0)
        windowX = (0.0, 0.0)
    }

    private static func polish(_ window: (Double, Double), with next: Double) -> (Double, Double) {
        let first = window.1
        return (first, first + 0.23 * (next - first))
    }
}
