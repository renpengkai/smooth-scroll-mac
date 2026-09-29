//
// ScrollUtils.swift
// SmoothScroll
// 滚动判断工具。改编自 Mos (https://github.com/Caldis/Mos) ScrollCore/ScrollUtils.swift,
// 原作者 Caldis, 以 CC BY-NC 4.0 授权; 本文件有删改。
//

import Cocoa

/// 只在主线程 (event tap 回调所在线程) 使用
final class ScrollUtils {

    static let shared = ScrollUtils()
    private init() {}

    private static let syntheticSmoothEventMarker: Int64 = 0x4D4F53534D4F4F54

    static func markSyntheticSmoothEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticSmoothEventMarker)
    }

    static func isSyntheticSmoothEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticSmoothEventMarker
    }

    // MARK: - 事件目标应用

    private var cachedTargetPID: pid_t = 0
    private var cachedTargetApplication: NSRunningApplication?

    func runningApplication(from event: CGEvent) -> NSRunningApplication? {
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid <= 1 { return nil }
        if pid != cachedTargetPID {
            cachedTargetPID = pid
            cachedTargetApplication = NSRunningApplication(processIdentifier: pid)
        }
        return cachedTargetApplication
    }

    /// macOS 26 之前的 Launchpad 是分页的, 平滑滚动会让翻页失效
    func isLaunchpadActive(_ application: NSRunningApplication?) -> Bool {
        if #available(macOS 26.0, *) { return false }
        return application?.executableURL?.path == "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
    }

    // MARK: - Logitech Options

    private var logiPID: pid_t = 0
    private var logiCheckedAt: CFTimeInterval = 0

    // 按 5 秒缓存, 避免触控板用户每个滚动事件都枚举一次进程
    func logitechOptionsPID() -> pid_t {
        let now = CFAbsoluteTimeGetCurrent()
        if now - logiCheckedAt > 5.0 {
            logiCheckedAt = now
            logiPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.logitech.manager.daemon")
                .first?.processIdentifier ?? 0
        }
        return logiPID
    }

    // MARK: - 远程桌面

    private static let remoteExecutableKeywords = ["screensharingd", "ScreensharingAgent", "ARDAgent"]
    private static let remoteBundleIdentifiers: Set<String> = [
        "com.teamviewer.TeamViewer",
        "com.teamviewer.TeamViewerHost",
        "com.anydesk.anydesk",
        "com.parsec.www",
        "com.rustdesk.RustDesk",
        "com.microsoft.rdc.macos",
        "com.realvnc.vncviewer",
        "com.tigervnc.vncviewer",
        "com.netease.uuremote",
    ]
    private var lastSourcePID: pid_t = 0
    private var lastSourceIsRemote = false

    /// 远程桌面主控端已经平滑过 (isContinuous=1) 的事件不再二次平滑
    func isRemoteSmoothedEvent(_ event: CGEvent) -> Bool {
        let sourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID == 0 { return false }
        if sourcePID != lastSourcePID {
            lastSourcePID = sourcePID
            lastSourceIsRemote = false
            if let app = NSRunningApplication(processIdentifier: sourcePID) {
                if let path = app.executableURL?.path {
                    lastSourceIsRemote = Self.remoteExecutableKeywords.contains { path.contains($0) }
                }
                if !lastSourceIsRemote, let bundleID = app.bundleIdentifier {
                    lastSourceIsRemote = Self.remoteBundleIdentifiers.contains(bundleID)
                }
            }
        }
        return lastSourceIsRemote && event.getDoubleValueField(.scrollWheelEventIsContinuous) == 1.0
    }
}
