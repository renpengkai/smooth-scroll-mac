//
// ScrollPhase.swift
// SmoothScroll
// 模拟触控板的 Phase 状态机。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollPhase.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改。
//
// 触控板事件序列:
// - 惯性滚动: [Hold] -> TrackingBegin -> TrackingOngoing -> TrackingEnd -> MomentumBegin -> MomentumOngoing -> MomentumEnd
// - 惯性中再次滑动: MomentumEnd 立即补发一帧, 然后重新从 TrackingBegin 开始
// - 非惯性滚动: [Hold] -> TrackingBegin -> TrackingOngoing -> TrackingEnd
//

import Foundation

enum Phase {
    case idle
    case hold
    case trackingBegin
    case trackingOngoing
    case trackingEnd
    case momentumBegin
    case momentumOngoing
    case momentumEnd
    case leave

    /// 写入 scrollWheelEventScrollPhase / scrollWheelEventMomentumPhase 的取值 (与系统触控板事件一致)
    var fieldValues: (scroll: Double, momentum: Double) {
        switch self {
        case .idle: return (0, 0)
        case .hold: return (128, 0)
        case .trackingBegin: return (1, 0)
        case .trackingOngoing: return (2, 0)
        case .trackingEnd: return (4, 0)
        case .momentumBegin: return (0, 1)
        case .momentumOngoing: return (0, 2)
        case .momentumEnd: return (0, 3)
        case .leave: return (8, 0)
        }
    }
}

/// 非线程安全: 所有调用都必须持有 ScrollPoster 的 stateLock
final class ScrollPhase {

    static let shared = ScrollPhase()
    private init() {}

    struct TransitionPlan {
        let queue: [(Phase, Phase?)]
        let target: (Phase, Phase?)?

        var isEmpty: Bool { queue.isEmpty && target == nil }
    }

    private(set) var phase: Phase = .idle
    // 下一帧发送完毕后自动切换到的阶段
    private var pendingPhaseAfterDelivery: Phase?

    private func plan(extra queue: [(Phase, Phase?)] = [], target: (Phase, Phase?)? = nil) -> TransitionPlan {
        TransitionPlan(queue: queue, target: target)
    }

    func reset() {
        phase = .idle
        pendingPhaseAfterDelivery = nil
    }

    /// 每次检测到滚轮输入时调用, 根据是否被视为独立滚动返回阶段序列
    func onManualInputDetected(isSeparated: Bool) -> TransitionPlan {
        if phase == .momentumBegin || phase == .momentumOngoing {
            if isSeparated {
                return plan(extra: [(.momentumEnd, .idle), (.trackingBegin, .trackingOngoing)])
            }
            return plan(extra: [(.momentumEnd, .idle)], target: (.trackingBegin, .trackingOngoing))
        }
        if isSeparated {
            return plan(extra: [(.trackingBegin, .trackingOngoing)])
        }
        if phase == .trackingBegin || phase == .trackingOngoing {
            return plan(target: (.trackingOngoing, nil))
        }
        return plan(target: (.trackingBegin, .trackingOngoing))
    }

    /// 滚轮输入停止后调用
    func onManualInputEnded() -> TransitionPlan {
        switch phase {
        case .trackingBegin, .trackingOngoing:
            return plan(target: (.trackingEnd, nil))
        default:
            return plan()
        }
    }

    func onMomentumStart() -> TransitionPlan {
        switch phase {
        case .trackingEnd, .momentumEnd:
            return plan(target: (.momentumBegin, .momentumOngoing))
        case .momentumBegin:
            return plan(target: (.momentumOngoing, nil))
        default:
            return plan()
        }
    }

    func onMomentumOngoing() -> TransitionPlan {
        phase == .momentumBegin ? plan(target: (.momentumOngoing, nil)) : plan()
    }

    func onMomentumFinish() -> TransitionPlan {
        switch phase {
        case .momentumBegin, .momentumOngoing:
            return plan(target: (.momentumEnd, .idle))
        case .trackingBegin, .trackingOngoing, .trackingEnd:
            return plan(target: (.trackingEnd, .idle))
        default:
            return plan()
        }
    }

    func didDeliverFrame() {
        if let next = pendingPhaseAfterDelivery {
            phase = next
            pendingPhaseAfterDelivery = nil
        }
    }

    func apply(phase next: Phase, autoAdvance: Phase? = nil) {
        phase = next
        pendingPhaseAfterDelivery = autoAdvance
    }
}
