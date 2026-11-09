import CoreGraphics
import Foundation

/// Where a menu bar icon lives (DESIGN.md §3.13). Sections are set by where the icon
/// sits relative to KKit's dividers, so ⌘-dragging an icon moves it between them.
public enum MenuBarIconSection: String, Codable, CaseIterable, Sendable, Hashable {
    /// Right of the ‹ chevron: always in the menu bar.
    case shown
    /// Between the chevron and the Always Hidden divider: shown when the chevron is
    /// clicked (or hovered).
    case hidden
    /// Left of the Always Hidden divider: only in the drop-down bar, the Floating Bar,
    /// or while everything is shown.
    case alwaysHidden

    public var title: String {
        switch self {
        case .shown: String(localized: "Always Shown")
        case .hidden: String(localized: "Hidden")
        case .alwaysHidden: String(localized: "Always Hidden")
        }
    }
}

/// Another app's icon in the menu bar (a status item or a menu extra).
public struct MenuBarIcon: Identifiable, Hashable, Sendable {
    /// Stable while the app runs: "<bundle id>/<identifier, title or index>".
    public var id: String
    public var pid: Int32
    public var bundleID: String?
    public var appName: String
    /// The app bundle, for its icon.
    public var appURL: URL?
    /// What the icon calls itself to VoiceOver ("Wi-Fi", "Dropbox"); may be empty.
    public var title: String
    /// In AppKit global coordinates (bottom-left origin, like `NSScreen.frame`). Hidden
    /// icons are far off the left edge of the screen.
    public var frame: CGRect
    public var section: MenuBarIconSection
    /// Fully on a screen and clear of the notch, so it can be seen and clicked.
    public var isOnScreen: Bool
    /// macOS keeps some icons in place (the clock, Control Center).
    public var canMove: Bool
    /// The icon's window (`CGWindowID`), for a picture of it. `nil` when not found.
    public var windowID: UInt32?

    public init(
        id: String,
        pid: Int32,
        bundleID: String? = nil,
        appName: String,
        appURL: URL? = nil,
        title: String = "",
        frame: CGRect,
        section: MenuBarIconSection,
        isOnScreen: Bool = true,
        canMove: Bool = true,
        windowID: UInt32? = nil
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.appURL = appURL
        self.title = title
        self.frame = frame
        self.section = section
        self.isOnScreen = isOnScreen
        self.canMove = canMove
        self.windowID = windowID
    }

    /// "Wi-Fi", or the app's name when the icon has no title of its own.
    public var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    /// "Control Center" under "Wi-Fi"; `nil` when the title is the app's name.
    public var detail: String? {
        displayName == appName ? nil : appName
    }
}

/// What happened to KKit's ‹ chevron.
public enum MenuBarChevronEvent: Sendable, Hashable {
    /// A click. `alternate` is ⌥-click or right-click.
    case click(alternate: Bool)
    /// The pointer came onto it.
    case hover
}

/// Tighter icon spacing in the menu bar (`NSStatusItemSpacing` and
/// `NSStatusItemSelectionPadding` for the current host).
public enum MenuBarIconSpacing: String, Codable, CaseIterable, Sendable, Hashable {
    case system
    case comfortable
    case compact
    case tight

    public var title: String {
        switch self {
        case .system: String(localized: "macOS default")
        case .comfortable: String(localized: "Comfortable")
        case .compact: String(localized: "Compact")
        case .tight: String(localized: "Tight")
        }
    }

    /// Points between icons and around each icon's highlight; `nil` for macOS's own.
    public var values: (spacing: Int, padding: Int)? {
        switch self {
        case .system: nil
        case .comfortable: (12, 10)
        case .compact: (8, 6)
        case .tight: (4, 4)
        }
    }
}

public struct MenuBarItemsError: LocalizedError, Sendable, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public static let needsAccessibility = MenuBarItemsError(String(localized: "Allow Accessibility for KKit to find and open menu bar icons."))
    public static let iconGone = MenuBarItemsError(String(localized: "That menu bar icon isn't there any more."))
    public static let cannotMove = MenuBarItemsError(String(localized: "macOS keeps that icon where it is."))
    public static let notInstalled = MenuBarItemsError(String(localized: "Menu Bar Manager isn't in the menu bar."))
    public static let moveFailed = MenuBarItemsError(String(localized: "The icon didn't move. Try ⌘-dragging it instead."))
}

/// Other apps' menu bar icons and KKit's dividers that hide them (ARCHITECTURE.md §7).
///
/// This is the most fragile part of KKit: it relies on how macOS lays out status items.
/// Hiding uses KKit's own divider status items, which grow very long to push the icons
/// left of them off the screen, so it needs no permission and fails open (quit KKit
/// and every icon is back). Listing and opening icons needs Accessibility; pictures of
/// icons need Screen Recording (through `ScreenCaptureService`, by `windowID`).
@MainActor
public protocol MenuBarItemsService: AnyObject, Sendable {
    /// Accessibility is granted (listing, opening and moving icons).
    var isTrusted: Bool { get }

    /// Puts the chevron and dividers in the menu bar, everything hidden. Calling it
    /// again changes whether there's an Always Hidden divider.
    func install(alwaysHiddenSection: Bool, onChevron: @escaping @MainActor (MenuBarChevronEvent) -> Void)
    /// Takes them out again; every icon comes back.
    func uninstall()
    var isInstalled: Bool { get }
    var hasAlwaysHiddenSection: Bool { get }
    /// The user dragged KKit's dividers into the wrong order (Always Hidden right of
    /// the chevron), so sections can't be told apart. `resetDividers` fixes it.
    var dividersOutOfOrder: Bool { get }

    /// The sections whose icons are in the menu bar right now. `.shown` is implied;
    /// `.alwaysHidden` implies `.hidden`.
    var revealed: Set<MenuBarIconSection> { get }
    func reveal(_ sections: Set<MenuBarIconSection>)

    /// The chevron's frame in AppKit global coordinates, to put the drop-down bar under.
    var chevronFrame: CGRect? { get }

    /// Every other app's icon, left to right. Skips KKit's own.
    func icons() async -> [MenuBarIcon]
    /// Opens the icon's menu, as a click would. The icon must be on screen for apps
    /// that only answer real clicks, so reveal its section first.
    func press(_ icon: MenuBarIcon) async throws
    /// Moves the icon into a section with a ⌘-drag, the way you'd do it by hand. Shows
    /// every section while it works and puts things back after.
    func move(_ icon: MenuBarIcon, to section: MenuBarIconSection) async throws
    /// Puts the chevron and dividers back at the left end of the icons, in order.
    func resetDividers()

    /// Whether a menu (of any app) is open, so hiding icons now would pull it away.
    var isMenuOpen: Bool { get }

    var iconSpacing: MenuBarIconSpacing { get }
    /// Apps pick it up when they next open; logging out applies it everywhere.
    func setIconSpacing(_ spacing: MenuBarIconSpacing)
}

public extension MenuBarItemsService {
    /// `.shown` plus what `revealed` says.
    func isRevealed(_ section: MenuBarIconSection) -> Bool {
        section == .shown || revealed.contains(section)
    }
}
