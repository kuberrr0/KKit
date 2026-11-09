import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI
import Testing
@testable import KKitHosts

@MainActor
struct IslandModelTests {
    private func activity(_ id: String, _ priority: IslandPriority, compact: Bool = true) -> IslandActivity {
        IslandActivity(
            id: id,
            title: id,
            symbol: "circle",
            priority: priority,
            compactLeading: compact ? AnyView(Text(id)) : nil,
            expanded: AnyView(Text(id))
        )
    }

    @Test func highestPriorityWinsTheCompactIsland() {
        let model = IslandModel()
        model.upsert(activity("awake", .low), owner: "power")
        model.upsert(activity("timer", .normal), owner: "timer")
        model.upsert(activity("inUse", .high), owner: "privacyIndicator")
        #expect(model.compactEntry?.activity.id == "inUse")
        #expect(model.orderedEntries.map(\.activity.id) == ["inUse", "timer", "awake"])
    }

    @Test func newestWinsAmongEquals() {
        let model = IslandModel()
        model.upsert(activity("a", .normal), owner: "timer")
        model.upsert(activity("b", .normal), owner: "timer")
        #expect(model.compactEntry?.activity.id == "b")
    }

    @Test func activitiesWithoutEarsAreSkipped() {
        let model = IslandModel()
        model.upsert(activity("pageOnly", .critical, compact: false), owner: "x")
        model.upsert(activity("awake", .low), owner: "power")
        #expect(model.compactEntry?.activity.id == "awake")
    }

    @Test func presentingAgainReplaces() {
        let model = IslandModel()
        let first = model.upsert(activity("timer", .normal), owner: "timer")
        let second = model.upsert(activity("timer", .high), owner: "timer")
        #expect(model.entries.count == 1)
        #expect(!model.contains(token: first))
        #expect(model.contains(token: second))
        // A stale handle can't update or remove the new one.
        #expect(!model.update(activity("timer", .low), owner: "timer", token: first))
        model.remove(token: first)
        #expect(model.entries.count == 1)
    }

    @Test func updateKeepsThePlaceInLine() {
        let model = IslandModel()
        let token = model.upsert(activity("a", .normal), owner: "timer")
        model.upsert(activity("b", .normal), owner: "timer")
        #expect(model.update(activity("a", .normal), owner: "timer", token: token))
        #expect(model.compactEntry?.activity.id == "b")
    }

    @Test func removingAnOwnerClearsItsHUDAndSelection() {
        let model = IslandModel()
        model.upsert(activity("timer", .normal), owner: "timer")
        model.showHUD(IslandHUD(id: "done", symbol: "bell"), owner: "timer")
        let entry = model.entries[0]
        model.expand(on: 1, page: IslandPageItem.activityPageID(entry))
        model.removeAll(owner: "timer")
        #expect(model.entries.isEmpty)
        #expect(model.hud == nil)
        #expect(model.selectedPageID == nil)
    }

    @Test func hudTokens() {
        let model = IslandModel()
        let first = model.showHUD(IslandHUD(id: "volume", symbol: "speaker"), owner: "volume")
        let second = model.showHUD(IslandHUD(id: "volume", symbol: "speaker", level: 0.5), owner: "volume")
        model.clearHUD(token: first)
        #expect(model.hud?.token == second)
        model.clearHUD(token: second)
        #expect(model.hud == nil)
    }

    @Test func pageItems() {
        let page = IslandPage(id: "power", title: "Power", symbol: "cup.and.saucer") { Text("Power") }
        let item = IslandPageItem.page(page, owner: "power")
        #expect(item.id == "page:power.power")
        let model = IslandModel()
        model.upsert(activity("awake", .low), owner: "power")
        #expect(IslandPageItem.activity(model.entries[0])?.id == "activity:power.awake")
    }
}

@MainActor
struct IslandDropAreaTests {
    @Test func picksTheZoneUnderTheCursor() {
        #expect(IslandDropZoneItem.index(at: 10, width: 300, count: 3) == 0)
        #expect(IslandDropZoneItem.index(at: 150, width: 300, count: 3) == 1)
        #expect(IslandDropZoneItem.index(at: 300, width: 300, count: 3) == 2)
        #expect(IslandDropZoneItem.index(at: -5, width: 300, count: 3) == 0)
        #expect(IslandDropZoneItem.index(at: 10, width: 300, count: 0) == nil)
    }

    @Test func showsAndHidesTheDropArea() {
        let model = IslandModel()
        #expect(model.dropDisplay == nil)
        model.showDropArea(on: 2)
        #expect(model.dropDisplay == 2)
        model.hideDropArea()
        #expect(model.dropDisplay == nil)
        #expect(model.hoveredDropZone == nil)
    }
}
