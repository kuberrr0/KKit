import AppKit
import Observation

/// What the switcher panel shows: the tiles, which one is selected, and the previews
/// that have arrived. Main actor only; the panel's views read it.
@MainActor
@Observable
final class SwitcherModel {
    private(set) var items: [SwitcherItem] = []
    private(set) var selectedIndex = 0
    /// Set once the window list has arrived for this opening.
    private(set) var isLoaded = false
    private(set) var layout = SwitcherLayout.make(count: 1, preferredTileWidth: PreviewSize.medium.tileWidth, showsPreviews: true, in: CGSize(width: 1440, height: 900))
    private(set) var showsPreviews = true
    /// Previews by `CGWindowID`.
    var thumbnails: [UInt32: CGImage] = [:]
    /// App icons by pid.
    private(set) var icons: [Int32: NSImage] = [:]

    var selected: SwitcherItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func reset() {
        items = []
        selectedIndex = 0
        isLoaded = false
        thumbnails = [:]
    }

    func load(_ items: [SwitcherItem], selectedIndex: Int, icons: [Int32: NSImage]) {
        self.items = items
        self.icons = icons
        self.selectedIndex = items.isEmpty ? 0 : min(max(selectedIndex, 0), items.count - 1)
        isLoaded = true
    }

    func setLayout(_ layout: SwitcherLayout, showsPreviews: Bool) {
        self.layout = layout
        self.showsPreviews = showsPreviews
    }

    /// Next/previous tile, wrapping around the ends.
    func move(by steps: Int) {
        guard !items.isEmpty, steps != 0 else { return }
        let count = items.count
        selectedIndex = ((selectedIndex + steps) % count + count) % count
    }

    /// The tile above or below; stays put at the top and bottom rows.
    func moveRow(by rows: Int) {
        let target = selectedIndex + rows * max(layout.columns, 1)
        guard items.indices.contains(target) else {
            // Down from a row above a short last row: go to the last tile.
            if rows > 0, selectedIndex / max(layout.columns, 1) < layout.rows - 1 {
                selectedIndex = items.count - 1
            }
            return
        }
        selectedIndex = target
    }

    func select(id: SwitcherItem.ID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }

    /// Drops tiles (a closed window, a quit app) and keeps a sensible selection.
    func remove(where shouldRemove: (SwitcherItem) -> Bool) {
        let selectedID = selected?.id
        items.removeAll(where: shouldRemove)
        if let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        } else {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
        }
    }

    func markHidden(pid: Int32) {
        for index in items.indices where items[index].pid == pid {
            items[index].isAppHidden = true
        }
    }
}
