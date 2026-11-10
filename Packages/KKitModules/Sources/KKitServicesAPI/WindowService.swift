import CoreGraphics
import Foundation

/// A window of another app, as the window service knows it. The reference stays valid
/// while the window exists.
public struct WindowHandle: Hashable, Sendable {
    /// The owning process.
    public var pid: Int32
    /// The service's own key for the window's accessibility element.
    public var key: UInt64

    public init(pid: Int32, key: UInt64) {
        self.pid = pid
        self.key = key
    }
}

public struct WindowInfo: Hashable, Sendable, Identifiable {
    public var ref: WindowHandle
    public var title: String
    public var appName: String
    public var bundleID: String?
    /// In AppKit global coordinates (bottom-left origin, like `NSScreen.frame`).
    public var frame: CGRect
    public var isMinimized: Bool
    public var isFullScreen: Bool
    /// Whether the window can be resized (some dialogs and utility windows can't).
    public var isResizable: Bool
    /// The window server's id (`CGWindowID`), for screenshots and previews, where it
    /// could be matched.
    public var windowID: UInt32?
    /// The owning app is hidden (⌘H).
    public var isAppHidden: Bool

    public init(
        ref: WindowHandle,
        title: String,
        appName: String,
        bundleID: String?,
        frame: CGRect,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        isResizable: Bool = true,
        windowID: UInt32? = nil,
        isAppHidden: Bool = false
    ) {
        self.ref = ref
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isResizable = isResizable
        self.windowID = windowID
        self.isAppHidden = isAppHidden
    }

    public var id: WindowHandle { ref }
}

public struct WindowError: LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public static let needsAccessibility = WindowError(String(localized: "Allow Accessibility for KKit to move windows."))
    public static let noWindow = WindowError(String(localized: "There's no window to move."))
}

/// Other apps' windows through the Accessibility API: find, read and move them.
/// ARCHITECTURE.md §7. Accessibility calls can be slow, so everything is `async` and
/// runs off the main thread with a short timeout per app.
@MainActor
public protocol WindowService: AnyObject, Sendable {
    /// Accessibility is granted.
    var isTrusted: Bool { get }
    /// The frontmost app's focused window.
    func focusedWindow() async -> WindowInfo?
    /// The window under a point in AppKit global coordinates.
    func window(at point: CGPoint) async -> WindowInfo?
    /// Standard windows of regular apps on the current Space, front to back.
    func visibleWindows() async -> [WindowInfo]
    func info(for window: WindowHandle) async -> WindowInfo?
    /// Moves and resizes. Some apps round sizes or refuse; read `info` to see the result.
    func setFrame(_ frame: CGRect, of window: WindowHandle) async
    func setOrigin(_ origin: CGPoint, of window: WindowHandle) async
    /// Brings the window and its app to the front, unhiding the app and un-minimising
    /// the window if needed.
    func raise(_ window: WindowHandle) async
    /// Every window the window switcher can offer: the current Space's windows front to
    /// back, then, when asked, minimised windows and windows of hidden apps (grouped by
    /// app). Windows on other Spaces aren't included. Each carries its `windowID` where
    /// the window server's list could be matched.
    func switchableWindows(includeMinimized: Bool, includeHiddenApps: Bool) async -> [WindowInfo]
    /// Presses the window's close button.
    func close(_ window: WindowHandle) async
    /// Brings an app to the front, unhiding it, even while KKit is in the background
    /// (where macOS 14's cooperative activation can ignore `NSRunningApplication.activate`).
    func activateApp(pid: Int32) async
    /// macOS 15's "Tile by dragging windows to screen edges" is on.
    var isSystemEdgeTilingEnabled: Bool { get }
}
