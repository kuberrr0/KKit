import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The Floating Bar's everyday sources: applications, files (Spotlight), System Settings
/// panes and the web. DESIGN.md §2.3 and §3.2.
@MainActor
public final class SearchFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "search",
        name: String(localized: "Search"),
        symbol: "magnifyingglass",
        summary: String(localized: "Find apps, files, System Settings and the web from the Floating Bar."),
        category: .productivity,
        enabledByDefault: true
    )

    private let context: FeatureContext
    private let apps: AppsProvider
    private let files: FilesProvider
    private let systemSettings: SystemSettingsProvider
    private let web: WebProvider

    public init(context: FeatureContext) {
        self.context = context
        let index = AppIndex()
        apps = AppsProvider(index: index)
        files = FilesProvider(search: { context.fileSearch }, settings: context.settings)
        systemSettings = SystemSettingsProvider()
        web = WebProvider(settings: context.settings, bookmarks: BookmarkIndex())
    }

    public func start() async throws {
        // Warm the app index so the first search is instant. It rescans in the
        // background when a search finds it more than ten minutes old.
        apps.warmUp()
    }

    public func stop() async {}

    // MARK: Contributions

    public var searchProviders: [any SearchProvider] {
        [apps, files, systemSettings, web]
    }

    public var commands: [Command] {
        [
            Command(
                id: "search.files",
                title: String(localized: "Search Files"),
                symbol: "doc.text.magnifyingglass",
                keywords: ["find", "spotlight", "folder"]
            ) { [weak self] _ in
                self?.context.floatingBar.show(query: FilesProvider.prefixText)
            },
            Command(
                id: "search.web",
                title: String(localized: "Search the Web"),
                symbol: "globe",
                keywords: ["google", "browser", "url", "bookmarks"]
            ) { [weak self] _ in
                self?.context.floatingBar.show(query: WebProvider.prefixText)
            },
            Command(
                id: "search.systemSettings",
                title: String(localized: "Search System Settings"),
                symbol: "gearshape",
                keywords: ["preferences", "pane"]
            ) { [weak self] _ in
                self?.context.floatingBar.show(query: SystemSettingsProvider.prefixText)
            },
        ]
    }

    public var resultActions: [ResultAction] {
        [
            ResultAction(
                id: "search.searchWeb",
                title: String(localized: "Search the Web for This"),
                symbol: "globe",
                appliesTo: { result in
                    if case .url = result.kind { return false }
                    return !result.title.isEmpty
                }
            ) { [web] result in
                web.searchDefaultEngine(for: result.title)
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane {
            SearchSettingsView()
        }
    }
}
