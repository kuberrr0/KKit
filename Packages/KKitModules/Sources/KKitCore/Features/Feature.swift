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

    // ── Contributions (all optional; read when the feature starts) ──────────
    // More arrive with their hosts: search providers and result actions (Floating
    // Bar, M2), Island pages (M1), extra menu bar items (M1).

    /// Actions, each reachable from hotkeys, the Floating Bar, URLs and Shortcuts.
    var commands: [Command] { get }
    /// Tiles for the menu bar popover grid.
    var quickToggles: [QuickToggle] { get }
    /// The feature's page in Settings.
    var settingsPane: SettingsPane? { get }
}

public extension Feature {
    var commands: [Command] { [] }
    var quickToggles: [QuickToggle] { [] }
    var settingsPane: SettingsPane? { nil }

    var manifest: FeatureManifest { Self.manifest }
}
