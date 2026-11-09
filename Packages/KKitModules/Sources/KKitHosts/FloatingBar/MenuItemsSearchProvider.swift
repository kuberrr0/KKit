import Foundation
import KKitCore
import KKitServicesAPI

/// The frontmost app's menu items under `m ` (DESIGN.md §2.3), through the
/// Accessibility API, and, while the Menu Bar Manager runs, the menu bar icons (hidden
/// ones too), which it publishes as `MenuBarIconsServicing`.
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
    private let menuBarIcons: @MainActor () -> (any MenuBarIconsServicing)?

    public init(
        accessibility: any AccessibilityService,
        menuBarIcons: @escaping @MainActor () -> (any MenuBarIconsServicing)? = { nil },
        requestAccess: @escaping @MainActor () -> Void
    ) {
        self.accessibility = accessibility
        self.menuBarIcons = menuBarIcons
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
        let app = accessibility.frontmostApp()
        let iconSource = menuBarIcons()
        guard app != nil || iconSource != nil else { return .single([]) }
        let accessibility = self.accessibility
        return .task {
            var results: [SearchResult] = []
            if let app {
                let items = await accessibility.menuItems(of: app.pid)
                results += Self.rank(items, query: query).map { Self.result(for: $0, app: app, accessibility: accessibility) }
            }
            if let iconSource, !Task.isCancelled {
                let icons = await iconSource.searchableIcons()
                results += Self.rank(icons, query: query).map { Self.result(for: $0, source: iconSource) }
            }
            return results
        }
    }

    /// Icons matching the query (by their name and app), best first; all of them for
    /// an empty query.
    static func rank(_ icons: [MenuBarIcon], query: SearchQuery) -> [(icon: MenuBarIcon, score: Double)] {
        let text = query.trimmed
        guard !text.isEmpty else {
            return icons.map { ($0, 0.6) }
        }
        return icons
            .compactMap { icon -> (icon: MenuBarIcon, score: Double)? in
                guard let score = FuzzyMatch.score(text, title: icon.displayName, keywords: [icon.appName, "menu bar icon"]) else {
                    return nil
                }
                return (icon, score)
            }
            .sorted { $0.score > $1.score }
    }

    static func result(for entry: (icon: MenuBarIcon, score: Double), source: any MenuBarIconsServicing) -> SearchResult {
        let icon = entry.icon
        let place = switch icon.section {
        case .shown: icon.isOnScreen ? String(localized: "Menu bar icon") : String(localized: "Menu bar icon · Behind the notch")
        case .hidden: String(localized: "Menu bar icon · Hidden")
        case .alwaysHidden: String(localized: "Menu bar icon · Always Hidden")
        }
        return SearchResult(
            id: "menuBarIcon:\(icon.id)",
            title: icon.displayName,
            subtitle: icon.detail.map { "\(place) · \($0)" } ?? place,
            icon: icon.appURL.map { ResultIcon.file($0) } ?? .symbol("menubar.rectangle"),
            score: entry.score,
            kind: .custom,
            actionTitle: String(localized: "Open"),
            perform: {
                // Let the Floating Bar close before the menu opens.
                try? await Task.sleep(for: .milliseconds(80))
                try await source.open(icon)
            }
        )
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
