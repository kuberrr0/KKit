import CoreGraphics
import KKitServicesAPI

/// A running app, as the switcher needs to know it.
struct SwitcherApp: Equatable, Sendable {
    var pid: Int32
    var name: String
    var bundleID: String?
    var isHidden: Bool
}

/// One tile in the switcher: a window, or an app with no window on this Space.
struct SwitcherItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case window(WindowHandle)
        case app
    }

    let id: String
    let kind: Kind
    let pid: Int32
    let appName: String
    let bundleID: String?
    let title: String
    /// `CGWindowID`, for the preview.
    let windowID: UInt32?
    var isMinimized: Bool
    var isAppHidden: Bool

    init(window: WindowInfo) {
        id = "w\(window.ref.pid)-\(window.ref.key)"
        kind = .window(window.ref)
        pid = window.ref.pid
        appName = window.appName
        bundleID = window.bundleID
        title = window.title
        windowID = window.windowID.flatMap { $0 == 0 ? nil : $0 }
        isMinimized = window.isMinimized
        isAppHidden = window.isAppHidden
    }

    init(app: SwitcherApp) {
        id = "a\(app.pid)"
        kind = .app
        pid = app.pid
        appName = app.name
        bundleID = app.bundleID
        title = ""
        windowID = nil
        isMinimized = false
        isAppHidden = app.isHidden
    }

    var window: WindowHandle? {
        if case .window(let handle) = kind { handle } else { nil }
    }

    /// The window's title, or the app's name for untitled windows and apps.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}

/// Builds the switcher's list and picks the first selection.
enum SwitcherList {
    /// More than this many tiles would be too small to read.
    static let limit = 60

    /// Windows on this Space front to back (most recently used first), then minimised
    /// windows and hidden apps' windows, then apps with no windows, those two groups by
    /// how recently each app was in front.
    ///
    /// - Parameters:
    ///   - windows: from `WindowService.switchableWindows`, on-screen ones first.
    ///   - apps: regular running apps.
    ///   - recentPIDs: apps in the order they were last in front, most recent first.
    static func build(
        windows: [WindowInfo],
        apps: [SwitcherApp],
        recentPIDs: [Int32],
        includeAppsWithoutWindows: Bool
    ) -> [SwitcherItem] {
        var rank: [Int32: Int] = [:]
        for (index, pid) in recentPIDs.enumerated() where rank[pid] == nil {
            rank[pid] = index
        }
        func byRecency<T>(_ values: [T], pid: (T) -> Int32) -> [T] {
            values.enumerated().sorted { lhs, rhs in
                let left = rank[pid(lhs.element)] ?? Int.max
                let right = rank[pid(rhs.element)] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }.map(\.element)
        }

        let visible = windows.filter { !$0.isMinimized && !$0.isAppHidden }
        let tucked = byRecency(windows.filter { $0.isMinimized || $0.isAppHidden }, pid: { $0.ref.pid })
        var items = (visible + tucked).map(SwitcherItem.init(window:))
        if includeAppsWithoutWindows {
            let withWindows = Set(items.map(\.pid))
            let windowless = apps.filter { !withWindows.contains($0.pid) }
            items += byRecency(windowless, pid: { $0.pid }).map(SwitcherItem.init(app:))
        }
        // The same window listed twice would confuse the selection.
        var seen: Set<String> = []
        items = items.filter { seen.insert($0.id).inserted }
        return Array(items.prefix(limit))
    }

    /// The tile selected when the switcher opens: the one after the frontmost app's
    /// window (the previous window, like ⌘Tab's previous app), or the last one when
    /// opened backwards with ⇧.
    static func initialIndex(for items: [SwitcherItem], frontmostPID: Int32?, backwards: Bool) -> Int {
        guard !items.isEmpty else { return 0 }
        if backwards {
            return items.count - 1
        }
        guard items.count > 1 else { return 0 }
        return items[0].pid == frontmostPID ? 1 : 0
    }
}
