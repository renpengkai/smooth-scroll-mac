//
// ScrollDispatchContext.swift
// SmoothScroll
// 合成滚动事件的模板与投递。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollDispatchContext.swift,
// 以 CC BY-NC 4.0 授权; 本文件有删改。
//

import Cocoa
import os

final class ScrollDispatchContext {

    static let shared = ScrollDispatchContext()
    private init() {}

    struct PostingSnapshot {
        let event: CGEvent
        let targetPID: pid_t
        let generation: UInt64
        let capturedAt: CFTimeInterval
    }

    private var eventTemplate: CGEvent?
    private var targetPID: pid_t = 0
    private var generation: UInt64 = 0
    private var updatedAt: CFTimeInterval = 0.0
    private var lock = os_unfair_lock_s()
    private let postQueue = DispatchQueue(label: "smoothscroll.poster.post", qos: .userInteractive)
    // TTL 只是投递兜底, 需覆盖最长惯性减速阶段 (通常 1-3s, 极端约 5s)
    private let eventTTL: CFTimeInterval = 5.0

    @discardableResult
    func capture(event: CGEvent) -> Bool {
        guard let template = event.copy() else { return false }
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        os_unfair_lock_lock(&lock)
        eventTemplate = template
        targetPID = pid
        updatedAt = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&lock)
        return true
    }

    func advanceGeneration() {
        os_unfair_lock_lock(&lock)
        generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    func clearContext() {
        os_unfair_lock_lock(&lock)
        eventTemplate = nil
        targetPID = 0
        updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    func invalidateAll() {
        os_unfair_lock_lock(&lock)
        generation &+= 1
        eventTemplate = nil
        targetPID = 0
        updatedAt = 0.0
        os_unfair_lock_unlock(&lock)
    }

    func preparePostingSnapshot() -> PostingSnapshot? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard targetPID != 0, let clone = eventTemplate?.copy() else { return nil }
        return PostingSnapshot(event: clone, targetPID: targetPID, generation: generation, capturedAt: updatedAt)
    }

    func enqueue(_ snapshot: PostingSnapshot) {
        postQueue.async { [self] in
            os_unfair_lock_lock(&lock)
            let valid = snapshot.generation == generation
                && CFAbsoluteTimeGetCurrent() - snapshot.capturedAt <= eventTTL
            os_unfair_lock_unlock(&lock)
            guard valid else { return }
            // 直投目标进程而不是重新走 session tap 链: 不依赖 tap proxy 的生命周期,
            // 且惯性阶段光标移到别的窗口时, 滚动仍然留在最初的目标进程里
            snapshot.event.postToPid(snapshot.targetPID)
        }
    }
}
