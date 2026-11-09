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
