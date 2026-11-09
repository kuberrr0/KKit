import CoreGraphics
import Foundation

/// A window of another app, as the window service knows it. The reference stays valid
/// while the window exists.
public struct WindowRef: Hashable, Sendable {
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
    public var ref: WindowRef
    public var title: String
    public var appName: String
    public var bundleID: String?
    /// In AppKit global coordinates (bottom-left origin, like `NSScreen.frame`).
    public var frame: CGRect
    public var isMinimized: Bool
    public var isFullScreen: Bool
    /// Whether the window can be resized (some dialogs and utility windows can't).
    public var isResizable: Bool

    public init(
        ref: WindowRef,
        title: String,
        appName: String,
        bundleID: String?,
        frame: CGRect,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        isResizable: Bool = true
    ) {
        self.ref = ref
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isResizable = isResizable
    }

    public var id: WindowRef { ref }
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
    func info(for window: WindowRef) async -> WindowInfo?
    /// Moves and resizes. Some apps round sizes or refuse; read `info` to see the result.
    func setFrame(_ frame: CGRect, of window: WindowRef) async
    func setOrigin(_ origin: CGPoint, of window: WindowRef) async
    /// Brings the window and its app to the front.
    func raise(_ window: WindowRef) async
    /// macOS 15's "Tile by dragging windows to screen edges" is on.
    var isSystemEdgeTilingEnabled: Bool { get }
}
