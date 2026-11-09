import Foundation

/// The app in front.
public struct FrontmostApp: Hashable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var name: String

    public init(pid: Int32, bundleID: String?, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

/// One item in an app's menu bar: "File › Export › PDF…".
public struct MenuItemInfo: Hashable, Sendable, Identifiable {
    /// The titles from the menu bar down, e.g. `["File", "Export", "PDF…"]`.
    public var path: [String]
    /// "⇧⌘S"
    public var shortcut: String?
    public var isEnabled: Bool
    public var isChecked: Bool
    public var pid: Int32

    public init(path: [String], shortcut: String? = nil, isEnabled: Bool = true, isChecked: Bool = false, pid: Int32) {
        self.path = path
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.pid = pid
    }

    public var id: String { "\(pid):" + path.joined(separator: "\u{1F}") }
    public var title: String { path.last ?? "" }
    /// "File › Export"
    public var parentPath: String { path.dropLast().joined(separator: " › ") }
}

public struct AccessibilityError: LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public static let needsAccessibility = AccessibilityError(String(localized: "Allow Accessibility for KKit to use other apps' menus."))
    public static let itemGone = AccessibilityError(String(localized: "That menu item isn't there any more."))
}

/// Reading other apps through the Accessibility API: the app in front, its menus,
/// the selected text. ARCHITECTURE.md §7.
@MainActor
public protocol AccessibilityService: AnyObject, Sendable {
    var isTrusted: Bool { get }
    /// The frontmost app that isn't KKit.
    func frontmostApp() -> FrontmostApp?
    /// Every menu item of an app's menu bar except the Apple menu, depth first. Cached
    /// for a few seconds per app.
    func menuItems(of pid: Int32) async -> [MenuItemInfo]
    /// Clicks a menu item.
    func press(_ item: MenuItemInfo) async throws
    /// The selected text in the focused element of the frontmost app.
    func selectedText() async -> String?
}
