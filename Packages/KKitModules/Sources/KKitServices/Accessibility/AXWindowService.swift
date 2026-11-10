import AppKit
import ApplicationServices
import CoreGraphics
import KKitCore
import KKitServicesAPI

/// Other apps' windows through the Accessibility API (ARCHITECTURE.md §7).
///
/// The `AXUIElement`s live in an actor, off the main thread, because a busy app can
/// take a while to answer (each app gets a 0.3 s timeout). Frames cross the boundary
/// in AppKit coordinates.
@MainActor
public final class AXWindowService: WindowService {
    private let engine = AXWindowEngine()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func focusedWindow() async -> WindowInfo? {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID else { return nil }
        guard let raw = await engine.focusedWindow(pid: app.processIdentifier) else { return nil }
        return decorate(raw)
    }

    public func window(at point: CGPoint) async -> WindowInfo? {
        guard isTrusted else { return nil }
        // Hit-testing a point over one of KKit's own windows would make KKit answer the
        // Accessibility query itself, off the main thread, which crashes SwiftUI. Ask the
        // window server who's there first. Click-through panels (tints, the snap
        // preview) don't count as KKit's, but with one there the system-wide hit test is
        // skipped and the window is found through its own app instead.
        let flipped = AX.flip(point)
        let clickThrough = Set((NSApp?.windows ?? []).filter(\.ignoresMouseEvents).map(\.windowNumber))
        if Self.topWindowOwner(at: flipped, skipping: clickThrough) == ownPID {
            return nil
        }
        let ownWindowThere = Self.topWindowOwner(at: flipped) == ownPID
        let candidates = Self.onScreenWindows()
            .filter { $0.pid != ownPID && $0.bounds.contains(flipped) }
        guard let raw = await engine.window(at: flipped, hitTest: !ownWindowThere, ownPID: ownPID, fallbacks: candidates) else { return nil }
        return decorate(raw)
    }

    public func visibleWindows() async -> [WindowInfo] {
        guard isTrusted else { return [] }
        let listed = Self.onScreenWindows().filter { $0.pid != ownPID }
        return await engine.windows(matching: listed).compactMap(decorate)
    }

    public func info(for window: WindowHandle) async -> WindowInfo? {
        guard let raw = await engine.info(window.key) else { return nil }
        return decorate(raw)
    }

    public func setFrame(_ frame: CGRect, of window: WindowHandle) async {
        await engine.setFrame(AX.flip(frame), key: window.key)
    }

    public func setOrigin(_ origin: CGPoint, of window: WindowHandle) async {
        guard let current = await engine.info(window.key) else { return }
        // AppKit origin is the bottom-left corner; Accessibility wants the top-left.
        let flipped = AX.flip(CGRect(origin: origin, size: current.frame.size))
        await engine.setPosition(flipped.origin, key: window.key)
    }

    public func raise(_ window: WindowHandle) async {
        guard window.pid != ownPID else { return }
        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true {
            app?.unhide()
        }
        await engine.raise(window.key)
        app?.activate()
    }

    public func switchableWindows(includeMinimized: Bool, includeHiddenApps: Bool) async -> [WindowInfo] {
        guard isTrusted else { return [] }
        let onScreen = Self.onScreenWindows().filter { $0.pid != ownPID }
        let offScreen = Self.offScreenWindows().filter { $0.pid != ownPID }
        // Never KKit itself: answering its own Accessibility queries off the main thread
        // crashes SwiftUI.
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
            .map { AXWindowEngine.AppEntry(pid: $0.processIdentifier, isHidden: $0.isHidden) }
        let raws = await engine.switchableWindows(
            onScreen: onScreen,
            offScreen: offScreen,
            apps: apps,
            includeMinimized: includeMinimized,
            includeHiddenApps: includeHiddenApps
        )
        return raws.compactMap(decorate)
    }

    public func close(_ window: WindowHandle) async {
        guard window.pid != ownPID else { return }
        await engine.close(window.key)
    }

    public func activateApp(pid: Int32) async {
        guard pid != ownPID, let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden {
            app.unhide()
        }
        if isTrusted {
            await engine.makeFrontmost(pid: pid)
        }
        app.activate()
    }

    public var isSystemEdgeTilingEnabled: Bool {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) else {
            return false
        }
        let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        return (defaults?.object(forKey: "EnableTilingByEdgeDrag") as? Bool) ?? true
    }

    // MARK: Private

    private func decorate(_ raw: AXWindowEngine.RawWindow) -> WindowInfo? {
        let app = NSRunningApplication(processIdentifier: raw.pid)
        return WindowInfo(
            ref: WindowHandle(pid: raw.pid, key: raw.key),
            title: raw.title,
            appName: app?.localizedName ?? raw.ownerName ?? "",
            bundleID: app?.bundleIdentifier,
            frame: AX.flip(raw.frame),
            isMinimized: raw.isMinimized,
            isFullScreen: raw.isFullScreen,
            isResizable: raw.isResizable,
            windowID: raw.windowID,
            isAppHidden: raw.isAppHidden
        )
    }

    /// The process owning the frontmost visible window (any level) at `point`, in Core
    /// Graphics coordinates.
    static func topWindowOwner(at point: CGPoint, skipping windowNumbers: Set<Int> = []) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in list {
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.contains(point),
                  ((entry[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  !windowNumbers.contains((entry[kCGWindowNumber as String] as? Int) ?? -1) else { continue }
            return entry[kCGWindowOwnerPID as String] as? Int32
        }
        return nil
    }

    /// Layer-0 windows on screen, front to back, from the window server (no permission
    /// needed for bounds and owners).
    static func onScreenWindows() -> [AXWindowEngine.ListedWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 40, bounds.height > 40 else { return nil }
            return AXWindowEngine.ListedWindow(
                pid: pid,
                bounds: bounds,
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                windowID: (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            )
        }
    }

    /// Layer-0 windows that aren't on screen: minimised, hidden apps', other Spaces'.
    static func offScreenWindows() -> [AXWindowEngine.ListedWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowIsOnscreen as String] as? Bool) != true,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 40, bounds.height > 40 else { return nil }
            return AXWindowEngine.ListedWindow(
                pid: pid,
                bounds: bounds,
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                windowID: (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            )
        }
    }
}

/// Holds the `AXUIElement`s. Frames here are in Accessibility coordinates.
actor AXWindowEngine {
    struct RawWindow: Sendable {
        var key: UInt64
        var pid: pid_t
        var title: String
        var ownerName: String?
        var frame: CGRect
        var isMinimized: Bool
        var isFullScreen: Bool
        var isResizable: Bool
        var windowID: UInt32?
        var isAppHidden = false
    }

    struct ListedWindow: Sendable {
        var pid: pid_t
        /// Core Graphics coordinates (top-left origin), like Accessibility.
        var bounds: CGRect
        var ownerName: String?
        /// `CGWindowID`
        var windowID: UInt32
    }

    struct AppEntry: Sendable {
        var pid: pid_t
        var isHidden: Bool
    }

    private var elements: [UInt64: AXUIElement] = [:]
    private var order: [UInt64] = []
    private var nextKey: UInt64 = 1
    private let maxRemembered = 300

    func focusedWindow(pid: pid_t) -> RawWindow? {
        let app = AX.application(pid)
        let window = AX.element(app, "AXFocusedWindow")
            ?? AX.element(app, "AXMainWindow")
            ?? AX.elements(app, "AXWindows").first
        return window.flatMap { raw(for: $0, pid: pid, ownerName: nil) }
    }

    func window(at point: CGPoint, hitTest: Bool, ownPID: pid_t, fallbacks: [ListedWindow]) -> RawWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, AX.messagingTimeout)
        var hit: AXUIElement?
        if hitTest, AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
           let hit, let pid = AX.pid(hit), pid != ownPID,
           let window = Self.enclosingWindow(of: hit) {
            return raw(for: window, pid: pid, ownerName: nil)
        }
        // Some apps don't answer hit-testing; match the window server's frontmost
        // window at that point to one of its app's windows instead.
        for listed in fallbacks {
            if let window = Self.matchingWindow(pid: listed.pid, bounds: listed.bounds) {
                return raw(for: window, pid: listed.pid, ownerName: listed.ownerName)
            }
        }
        return nil
    }

    func windows(matching listed: [ListedWindow]) -> [RawWindow] {
        var result: [RawWindow] = []
        var cache: [pid_t: [AXUIElement]] = [:]
        var used: Set<UInt64> = []
        for entry in listed {
            let candidates = cache[entry.pid] ?? Self.standardWindows(of: entry.pid)
            cache[entry.pid] = candidates
            guard let window = candidates.first(where: { Self.close(AX.frame($0), entry.bounds) }),
                  var raw = raw(for: window, pid: entry.pid, ownerName: entry.ownerName),
                  !used.contains(raw.key) else { continue }
            raw.windowID = entry.windowID
            used.insert(raw.key)
            result.append(raw)
        }
        return result
    }

    /// The window switcher's list: on-screen windows front to back, then minimised
    /// windows and hidden apps' windows, app by app. Windows that are neither (on another
    /// Space, or full screen) are left out.
    func switchableWindows(
        onScreen: [ListedWindow],
        offScreen: [ListedWindow],
        apps: [AppEntry],
        includeMinimized: Bool,
        includeHiddenApps: Bool
    ) -> [RawWindow] {
        var result = windows(matching: onScreen)
        var used = Set(result.map(\.key))
        for app in apps {
            guard includeMinimized || (app.isHidden && includeHiddenApps) else { continue }
            for window in Self.standardWindows(of: app.pid) {
                guard var raw = raw(for: window, pid: app.pid, ownerName: nil), !used.contains(raw.key) else { continue }
                if raw.isMinimized {
                    guard includeMinimized, !app.isHidden || includeHiddenApps else { continue }
                } else {
                    guard app.isHidden, includeHiddenApps else { continue }
                }
                raw.isAppHidden = app.isHidden
                let frame = raw.frame
                raw.windowID = offScreen.first { $0.pid == app.pid && Self.close(frame, $0.bounds) }?.windowID
                used.insert(raw.key)
                result.append(raw)
            }
        }
        return result
    }

    func info(_ key: UInt64) -> RawWindow? {
        guard let element = elements[key], let pid = AX.pid(element) else { return nil }
        return raw(for: element, pid: pid, ownerName: nil)
    }

    func setFrame(_ frame: CGRect, key: UInt64) {
        guard let window = elements[key], let pid = AX.pid(window) else { return }
        Self.withoutEnhancedUI(pid: pid) {
            // Size, position, size: the first size lets the move land on a smaller
            // screen, the second fixes a size the old screen clamped.
            AX.setSize(window, frame.size)
            AX.setPosition(window, frame.origin)
            AX.setSize(window, frame.size)
        }
    }

    func setPosition(_ point: CGPoint, key: UInt64) {
        guard let window = elements[key] else { return }
        AX.setPosition(window, point)
    }

    func raise(_ key: UInt64) {
        guard let window = elements[key] else { return }
        if AX.bool(window, "AXMinimized") == true {
            AX.set(window, "AXMinimized", kCFBooleanFalse)
        }
        // Making the app frontmost through Accessibility works even when macOS 14's
        // cooperative activation ignores `NSRunningApplication.activate()` from a
        // background app.
        if let pid = AX.pid(window) {
            AX.set(AX.application(pid), "AXFrontmost", kCFBooleanTrue)
        }
        AX.perform(window, "AXRaise")
        AX.set(window, "AXMain", kCFBooleanTrue)
    }

    func makeFrontmost(pid: pid_t) {
        AX.set(AX.application(pid), "AXFrontmost", kCFBooleanTrue)
    }

    func close(_ key: UInt64) {
        guard let window = elements[key], let button = AX.element(window, "AXCloseButton") else { return }
        AX.perform(button, "AXPress")
    }

    // MARK: Private

    private func raw(for window: AXUIElement, pid: pid_t, ownerName: String?) -> RawWindow? {
        guard let frame = AX.frame(window) else { return nil }
        return RawWindow(
            key: remember(window),
            pid: pid,
            title: AX.string(window, "AXTitle") ?? "",
            ownerName: ownerName,
            frame: frame,
            isMinimized: AX.bool(window, "AXMinimized") ?? false,
            isFullScreen: AX.bool(window, "AXFullScreen") ?? false,
            isResizable: AX.isSettable(window, "AXSize")
        )
    }

    private func remember(_ element: AXUIElement) -> UInt64 {
        for (key, existing) in elements where CFEqual(existing, element) {
            return key
        }
        let key = nextKey
        nextKey &+= 1
        elements[key] = element
        order.append(key)
        if order.count > maxRemembered {
            let dropped = order.removeFirst()
            elements[dropped] = nil
        }
        return key
    }

    private static func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        if AX.string(element, "AXRole") == "AXWindow" {
            return element
        }
        if let window = AX.element(element, "AXWindow") {
            return window
        }
        var current = element
        for _ in 0..<12 {
            guard let parent = AX.element(current, "AXParent") else { return nil }
            if AX.string(parent, "AXRole") == "AXWindow" {
                return parent
            }
            current = parent
        }
        return nil
    }

    private static func standardWindows(of pid: pid_t) -> [AXUIElement] {
        AX.elements(AX.application(pid), "AXWindows").filter { window in
            let subrole = AX.string(window, "AXSubrole")
            return subrole == nil || subrole == "AXStandardWindow" || subrole == "AXDialog"
        }
    }

    private static func matchingWindow(pid: pid_t, bounds: CGRect) -> AXUIElement? {
        standardWindows(of: pid).first { close(AX.frame($0), bounds) }
    }

    private static func close(_ frame: CGRect?, _ bounds: CGRect) -> Bool {
        guard let frame else { return false }
        return abs(frame.minX - bounds.minX) < 4 && abs(frame.minY - bounds.minY) < 4
            && abs(frame.width - bounds.width) < 4 && abs(frame.height - bounds.height) < 4
    }

    /// Chromium and Electron apps animate every Accessibility move while "enhanced user
    /// interface" is on, so it's switched off for the move and back on afterwards.
    private static func withoutEnhancedUI(pid: pid_t, _ work: () -> Void) {
        let app = AX.application(pid)
        let enhanced = AX.bool(app, "AXEnhancedUserInterface") == true
        if enhanced {
            AX.set(app, "AXEnhancedUserInterface", kCFBooleanFalse)
        }
        work()
        if enhanced {
            AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue)
        }
    }
}
