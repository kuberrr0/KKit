import KKitCore

/// Published by the Menu Bar Manager while it runs, so the Floating Bar's `m `
/// search can list menu bar icons (hidden ones too) next to the app's menu items and
/// open them the way the Menu Bar Manager does (showing hidden icons first).
@MainActor
public protocol MenuBarIconsServicing: AnyObject, Sendable {
    /// Every icon the manager knows, left to right.
    func searchableIcons() async -> [MenuBarIcon]
    /// Opens the icon's menu, showing its section for a moment if it's hidden.
    func open(_ icon: MenuBarIcon) async throws
}
