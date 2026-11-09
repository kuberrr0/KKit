import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import KKitHosts

@MainActor
struct MenuItemsSearchTests {
    private let items = [
        MenuItemInfo(path: ["File", "Save"], shortcut: "⌘S", pid: 42),
        MenuItemInfo(path: ["File", "Save As…"], shortcut: "⇧⌘S", pid: 42),
        MenuItemInfo(path: ["Edit", "Paste and Match Style"], pid: 42),
        MenuItemInfo(path: ["Edit", "Undo"], isEnabled: false, pid: 42),
    ]

    @Test func matchesTitlesAndSkipsDisabledItems() {
        let saves = MenuItemsSearchProvider.rank(items, query: SearchQuery(text: "save"))
        #expect(saves.first?.item.title == "Save")
        #expect(saves.count == 2)
        #expect(MenuItemsSearchProvider.rank(items, query: SearchQuery(text: "undo")).isEmpty)
        #expect(MenuItemsSearchProvider.rank(items, query: SearchQuery(text: "paste match")).first?.item.title == "Paste and Match Style")
    }

    @Test func emptyQueryListsEverythingEnabled() {
        #expect(MenuItemsSearchProvider.rank(items, query: SearchQuery(text: "")).count == 3)
    }

    @Test func parentPath() {
        #expect(items[1].parentPath == "File")
        #expect(MenuItemInfo(path: ["View", "Sort By", "Name"], pid: 1).parentPath == "View › Sort By")
    }
}

@MainActor
final class FakeMenuBarIcons: MenuBarIconsServicing {
    var icons: [MenuBarIcon]
    private(set) var opened: [String] = []

    init(icons: [MenuBarIcon]) {
        self.icons = icons
    }

    func searchableIcons() async -> [MenuBarIcon] { icons }

    func open(_ icon: MenuBarIcon) async throws {
        opened.append(icon.id)
    }
}

@MainActor
struct MenuBarIconsSearchTests {
    private let icons = [
        MenuBarIcon(id: "cc/wifi", pid: 1, bundleID: "com.apple.controlcenter", appName: "Control Center", title: "Wi-Fi", frame: CGRect(x: 1300, y: 958, width: 24, height: 24), section: .shown),
        MenuBarIcon(id: "dropbox/0", pid: 2, bundleID: "com.getdropbox.dropbox", appName: "Dropbox", frame: CGRect(x: -9000, y: 958, width: 24, height: 24), section: .hidden, isOnScreen: false),
    ]

    @Test func ranksIconsByNameAndApp() {
        #expect(MenuItemsSearchProvider.rank(icons, query: SearchQuery(text: "wifi")).first?.icon.id == "cc/wifi")
        #expect(MenuItemsSearchProvider.rank(icons, query: SearchQuery(text: "dropbox")).map(\.icon.id) == ["dropbox/0"])
        #expect(MenuItemsSearchProvider.rank(icons, query: SearchQuery(text: "")).count == 2)
    }

    @Test func iconsJoinTheMenuItems() async throws {
        let accessibility = FakeAccessibilityService()
        accessibility.items = [MenuItemInfo(path: ["File", "Save"], pid: 42)]
        let source = FakeMenuBarIcons(icons: icons)
        let provider = MenuItemsSearchProvider(accessibility: accessibility, menuBarIcons: { source }, requestAccess: {})
        var results: [SearchResult] = []
        for await batch in provider.results(for: SearchQuery(text: "")) {
            results = batch
        }
        #expect(results.map(\.title).contains("Save"))
        let dropbox = try #require(results.first(where: { $0.id == "menuBarIcon:dropbox/0" }))
        #expect(dropbox.title == "Dropbox")
        #expect(dropbox.subtitle == "Menu bar icon · Hidden")
        let wifi = try #require(results.first(where: { $0.id == "menuBarIcon:cc/wifi" }))
        #expect(wifi.subtitle == "Menu bar icon · Control Center")
        try await dropbox.perform?()
        #expect(source.opened == ["dropbox/0"])
    }

    @Test func iconsWithoutAnAppInFront() async {
        let accessibility = FakeAccessibilityService()
        accessibility.app = nil
        let provider = MenuItemsSearchProvider(accessibility: accessibility, menuBarIcons: { FakeMenuBarIcons(icons: self.icons) }, requestAccess: {})
        var results: [SearchResult] = []
        for await batch in provider.results(for: SearchQuery(text: "wi")) {
            results = batch
        }
        #expect(results.map(\.id) == ["menuBarIcon:cc/wifi"])
    }
}
