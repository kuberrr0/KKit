import Foundation
import KKitCore
import KKitServicesAPI

/// The frontmost app's menu items under `m ` (DESIGN.md §2.3), through the
/// Accessibility API. Menu bar icons join these with the Menu Bar Manager (M5).
@MainActor
public final class MenuItemsSearchProvider: SearchProvider {
    public let id = "menuItems"
    public let displayName = String(localized: "Menu Items")
    public let symbol = "filemenu.and.selection"
    public let prefix: String? = "m "
    /// Walking a big app's menus takes a moment, so only when asked for.
    public let includeInRootSearch = false

    private let accessibility: any AccessibilityService
    private let requestAccess: @MainActor () -> Void

    public init(accessibility: any AccessibilityService, requestAccess: @escaping @MainActor () -> Void) {
        self.accessibility = accessibility
        self.requestAccess = requestAccess
    }

    public func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        guard accessibility.isTrusted else {
            let requestAccess = self.requestAccess
            return .single([SearchResult(
                id: "menuItems.permission",
                title: String(localized: "Allow Accessibility to search menus"),
                subtitle: String(localized: "KKit reads the menus of the app in front"),
                icon: .symbol("accessibility"),
                score: 1,
                kind: .custom,
                actionTitle: String(localized: "Open Settings"),
                perform: { requestAccess() }
            )])
        }
        guard let app = accessibility.frontmostApp() else { return .single([]) }
        let accessibility = self.accessibility
        return .task {
            let items = await accessibility.menuItems(of: app.pid)
            return Self.rank(items, query: query).map { Self.result(for: $0, app: app, accessibility: accessibility) }
        }
    }

    /// Enabled items matching the query, best first; everything (in menu order) for an
    /// empty query.
    static func rank(_ items: [MenuItemInfo], query: SearchQuery) -> [(item: MenuItemInfo, score: Double)] {
        let enabled = items.filter(\.isEnabled)
        let text = query.trimmed
        guard !text.isEmpty else {
            return enabled.prefix(60).map { ($0, 0.5) }
        }
        return enabled
            .compactMap { item -> (item: MenuItemInfo, score: Double)? in
                guard let score = FuzzyMatch.score(text, title: item.title, keywords: [item.parentPath, item.path.joined(separator: " ")]) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { $0.score > $1.score }
    }

    private static func result(
        for entry: (item: MenuItemInfo, score: Double),
        app: FrontmostApp,
        accessibility: any AccessibilityService
    ) -> SearchResult {
        let item = entry.item
        return SearchResult(
            id: "menu:\(app.bundleID ?? app.name):\(item.path.joined(separator: "/"))",
            title: item.title,
            subtitle: ([app.name] + item.path.dropLast()).joined(separator: " › "),
            icon: .symbol(item.isChecked ? "checkmark" : "filemenu.and.selection"),
            score: entry.score,
            kind: .custom,
            accessory: item.shortcut,
            actionTitle: String(localized: "Click"),
            perform: {
                // Let the app get keyboard focus back from the Floating Bar first.
                try? await Task.sleep(for: .milliseconds(80))
                try await accessibility.press(item)
            }
        )
    }
}
