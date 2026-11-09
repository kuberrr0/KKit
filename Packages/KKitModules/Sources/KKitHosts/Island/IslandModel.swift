import Foundation
import KKitCore
import KKitServicesAPI
import Observation
import SwiftUI

/// The Island's state, shared by every Island panel: live activities, the current HUD,
/// and which panel is expanded on which page. Kept free of AppKit so it can be tested.
@MainActor
@Observable
public final class IslandModel {
    public struct Entry: Identifiable {
        public let owner: FeatureID
        public var activity: IslandActivity
        /// Changes every time the activity is presented again, so stale handles can tell.
        public let token: UUID
        /// Presentation order, newest last: breaks priority ties (newest wins).
        public let sequence: Int

        public var id: String { IslandModel.key(owner: owner, id: activity.id) }
    }

    public struct HUDEntry: Equatable {
        public var hud: IslandHUD
        public var owner: FeatureID
        public var token: UUID
    }

    public private(set) var entries: [Entry] = []
    public private(set) var hud: HUDEntry?
    /// The display whose panel is expanded, if any.
    public var expandedDisplay: UInt32?
    /// The selected page in the expanded Island.
    public var selectedPageID: String?
    /// The display whose Island shows the drop area, while something is dragged near
    /// the notch or over the Island.
    public var dropDisplay: UInt32?
    /// The drop zone under the cursor (`IslandDropZoneItem.id`).
    public var hoveredDropZone: String?

    private var sequence = 0

    public init() {}

    nonisolated static func key(owner: FeatureID, id: String) -> String {
        "\(owner.rawValue).\(id)"
    }

    // MARK: Activities

    /// Adds or replaces an activity. Returns its token.
    @discardableResult
    public func upsert(_ activity: IslandActivity, owner: FeatureID) -> UUID {
        let token = UUID()
        let key = Self.key(owner: owner, id: activity.id)
        sequence += 1
        let entry = Entry(owner: owner, activity: activity, token: token, sequence: sequence)
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        return token
    }

    /// Replaces the activity's content if `token` is still current.
    @discardableResult
    public func update(_ activity: IslandActivity, owner: FeatureID, token: UUID) -> Bool {
        let key = Self.key(owner: owner, id: activity.id)
        guard let index = entries.firstIndex(where: { $0.token == token }) else { return false }
        let old = entries[index]
        entries[index] = Entry(owner: owner, activity: activity, token: token, sequence: old.sequence)
        if old.id != key {
            entries.removeAll { $0.id == key && $0.token != token }
        }
        return true
    }

    public func remove(token: UUID) {
        entries.removeAll { $0.token == token }
        repairSelection()
    }

    public func removeAll(owner: FeatureID) {
        entries.removeAll { $0.owner == owner }
        if hud?.owner == owner {
            hud = nil
        }
        repairSelection()
    }

    public func contains(token: UUID) -> Bool {
        entries.contains { $0.token == token }
    }

    /// Whether the Island is expanded on this activity's page.
    public func isExpanded(token: UUID) -> Bool {
        guard expandedDisplay != nil, let entry = entries.first(where: { $0.token == token }) else { return false }
        return selectedPageID == IslandPageItem.activityPageID(entry)
    }

    /// Activities in display order: highest priority first, newest first among equals.
    public var orderedEntries: [Entry] {
        entries.sorted {
            if $0.activity.priority != $1.activity.priority {
                return $0.activity.priority > $1.activity.priority
            }
            return $0.sequence > $1.sequence
        }
    }

    /// The activity shown in the compact Island.
    public var compactEntry: Entry? {
        orderedEntries.first { $0.activity.compactLeading != nil || $0.activity.compactTrailing != nil }
    }

    // MARK: HUD

    @discardableResult
    public func showHUD(_ hud: IslandHUD, owner: FeatureID) -> UUID {
        let token = UUID()
        self.hud = HUDEntry(hud: hud, owner: owner, token: token)
        return token
    }

    public func clearHUD(token: UUID) {
        if hud?.token == token {
            hud = nil
        }
    }

    // MARK: Expansion

    public func expand(on display: UInt32, page: String? = nil) {
        expandedDisplay = display
        if let page {
            selectedPageID = page
        }
    }

    public func collapse() {
        expandedDisplay = nil
    }

    // MARK: Drop area

    public func showDropArea(on display: UInt32) {
        dropDisplay = display
    }

    public func hideDropArea() {
        dropDisplay = nil
        hoveredDropZone = nil
    }

    private func repairSelection() {
        guard let selected = selectedPageID, selected.hasPrefix(IslandPageItem.activityPrefix) else { return }
        let key = String(selected.dropFirst(IslandPageItem.activityPrefix.count))
        if !entries.contains(where: { $0.id == key }) {
            selectedPageID = nil
        }
    }
}

/// A page in the expanded Island: an activity's expanded view or a feature's page.
public struct IslandPageItem: Identifiable {
    static let activityPrefix = "activity:"
    static let pagePrefix = "page:"

    public let id: String
    public let title: String
    public let symbol: String
    public let makeView: @MainActor () -> AnyView

    @MainActor
    static func activity(_ entry: IslandModel.Entry) -> IslandPageItem? {
        guard let expanded = entry.activity.expanded else { return nil }
        return IslandPageItem(
            id: activityPrefix + entry.id,
            title: entry.activity.title,
            symbol: entry.activity.symbol,
            makeView: { expanded }
        )
    }

    @MainActor
    static func page(_ page: IslandPage, owner: FeatureID) -> IslandPageItem {
        IslandPageItem(
            id: pagePrefix + IslandModel.key(owner: owner, id: page.id),
            title: page.title,
            symbol: page.symbol,
            makeView: page.makeView
        )
    }

    static func activityPageID(_ entry: IslandModel.Entry) -> String {
        activityPrefix + entry.id
    }

    static func activityPageID(owner: FeatureID, activityID: String) -> String {
        activityPrefix + IslandModel.key(owner: owner, id: activityID)
    }

    static func pageID(owner: FeatureID, pageID: String) -> String {
        pagePrefix + IslandModel.key(owner: owner, id: pageID)
    }
}

/// A drop zone in the Island's drop area, with its owner.
public struct IslandDropZoneItem: Identifiable {
    public let owner: FeatureID
    public let zone: IslandDropZone

    public var id: String { IslandModel.key(owner: owner, id: zone.id) }

    /// Running features' zones, in order.
    @MainActor
    public static func collect(from features: [any Feature]) -> [IslandDropZoneItem] {
        features
            .flatMap { feature in
                feature.islandDropZones.map { IslandDropZoneItem(owner: type(of: feature).manifest.id, zone: $0) }
            }
            .sorted { $0.zone.order < $1.zone.order }
    }

    /// Which of `count` equal-width zones the point `x` (0…`width`) is over.
    public static func index(at x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0 else { return nil }
        let index = Int((x / width) * CGFloat(count))
        return min(max(index, 0), count - 1)
    }
}
