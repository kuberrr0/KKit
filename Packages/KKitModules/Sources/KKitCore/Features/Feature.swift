import Foundation

/// A KKit feature: a plug-in that contributes commands, toggles and a settings page to
/// the shared hosts, and uses shared services from its `FeatureContext`.
///
/// Features never import each other and never create their own windows, panels or
/// event taps. See ARCHITECTURE.md §4 and the recipe in §11.
@MainActor
public protocol Feature: AnyObject {
    static var manifest: FeatureManifest { get }

    /// Cheap. No side effects. Called when the feature is enabled.
    init(context: FeatureContext)

    /// Begin work: register observers, install hooks, publish services.
    /// Only called when the required permissions are granted.
    func start() async throws

    /// Undo everything `start()` did. Must be safe to call after a failed start.
    func stop() async

    // ── Contributions (all optional) ────────────────────────────────────────
    // `commands` are read once when the feature starts. The others are read by the
    // hosts while the feature runs, so they may depend on settings.
    // Search providers and result actions arrive with the Floating Bar (M2).

    /// Actions, each reachable from hotkeys, the Floating Bar, URLs and Shortcuts.
    var commands: [Command] { get }
    /// Tiles for the menu bar popover grid.
    var quickToggles: [QuickToggle] { get }
    /// Sections in the menu bar popover below the grid (sliders, stats strip).
    var menuBarSections: [MenuBarSection] { get }
    /// Standalone status items next to the KKit icon.
    var menuBarItems: [MenuBarItem] { get }
    /// Pages in the expanded Island.
    var islandPages: [IslandPage] { get }
    /// The feature's page in Settings.
    var settingsPane: SettingsPane? { get }
}

public extension Feature {
    var commands: [Command] { [] }
    var quickToggles: [QuickToggle] { [] }
    var menuBarSections: [MenuBarSection] { [] }
    var menuBarItems: [MenuBarItem] { [] }
    var islandPages: [IslandPage] { [] }
    var settingsPane: SettingsPane? { nil }

    var manifest: FeatureManifest { Self.manifest }
}
