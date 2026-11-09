import KKitCore
import SwiftUI

/// Which activity wins the compact Island when several are live
/// (DESIGN.md §2.2: recording › mic/camera in use › timer › Power).
public enum IslandPriority: Int, Sendable, Comparable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: IslandPriority, rhs: IslandPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How long an activity stays.
public enum IslandLifetime: Sendable, Equatable {
    /// Until the feature dismisses it.
    case ongoing
    /// Dismissed automatically after `seconds`.
    case transient(seconds: Double)
}

/// Something live in the Island: a timer, the Power indicator, mic in use.
///
/// The compact Island shows the highest-priority activity's two "ears" either side
/// of the notch. Expanding the Island shows each activity's `expanded` view as a page.
public struct IslandActivity: Identifiable {
    /// Unique within the feature. Presenting the same id again replaces it.
    public var id: String
    /// Page picker label and VoiceOver label: "Timer".
    public var title: String
    /// Page picker symbol.
    public var symbol: String
    public var priority: IslandPriority
    public var lifetime: IslandLifetime
    /// Left ear (keep it ~20 pt wide).
    public var compactLeading: AnyView?
    /// Right ear (up to ~70 pt wide).
    public var compactTrailing: AnyView?
    /// Shown when the Island is expanded on this activity.
    public var expanded: AnyView?
    /// Clicking the compact Island runs this instead of expanding it.
    public var onTap: (@MainActor () -> Void)?

    public init(
        id: String,
        title: String,
        symbol: String,
        priority: IslandPriority = .normal,
        lifetime: IslandLifetime = .ongoing,
        compactLeading: AnyView? = nil,
        compactTrailing: AnyView? = nil,
        expanded: AnyView? = nil,
        onTap: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.priority = priority
        self.lifetime = lifetime
        self.compactLeading = compactLeading
        self.compactTrailing = compactTrailing
        self.expanded = expanded
        self.onTap = onTap
    }
}

/// A transient HUD (volume, "Mic muted", "Battery 15%"). It covers the compact
/// Island for `duration` seconds, then the activities come back.
public struct IslandHUD: Sendable, Equatable {
    /// HUDs with the same id replace each other (dragging the volume updates one HUD).
    public var id: String
    public var symbol: String
    public var title: String?
    /// 0…1 draws a level bar.
    public var level: Double?
    /// Short trailing text: "62%".
    public var detail: String?
    public var tint: HUDTint
    public var duration: Double

    public enum HUDTint: Sendable, Equatable {
        case normal, accent, warning, critical
    }

    public init(
        id: String,
        symbol: String,
        title: String? = nil,
        level: Double? = nil,
        detail: String? = nil,
        tint: HUDTint = .normal,
        duration: Double = 1.5
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.level = level
        self.detail = detail
        self.tint = tint
        self.duration = duration
    }
}

/// Scrolling over the Island. The Volume feature uses it to change the volume.
public struct IslandScrollEvent: Sendable, Equatable {
    /// Positive = scrolled up / away from the user.
    public var deltaY: Double
    public var deltaX: Double
    /// Trackpad (pixel deltas) rather than a notched mouse wheel.
    public var isPrecise: Bool
    /// ⌥ was held: fine steps.
    public var isFine: Bool

    public init(deltaY: Double, deltaX: Double, isPrecise: Bool, isFine: Bool) {
        self.deltaY = deltaY
        self.deltaX = deltaX
        self.isPrecise = isPrecise
        self.isFine = isFine
    }
}

/// A live activity, returned by `present`.
@MainActor
public protocol IslandHandle: AnyObject {
    /// `false` once dismissed (by the feature, by its lifetime, or because the feature stopped).
    var isActive: Bool { get }
    func update(_ activity: IslandActivity)
    func dismiss()
}

/// The Island host, as features see it. Features use `context.island`, which fills in
/// `owner`; the host drops a feature's activities when it stops.
@MainActor
public protocol IslandService: AnyObject {
    @discardableResult
    func present(_ activity: IslandActivity, owner: FeatureID) -> any IslandHandle
    func showHUD(_ hud: IslandHUD, owner: FeatureID)
    func dismissAll(owner: FeatureID)
    /// One handler per feature; `nil` removes it. The newest handler gets scrolls.
    func setScrollHandler(_ handler: (@MainActor (IslandScrollEvent) -> Void)?, owner: FeatureID)
}

/// A feature's handle on the Island (`context.island`).
@MainActor
public struct FeatureIsland {
    public let owner: FeatureID
    public let service: any IslandService

    public init(owner: FeatureID, service: any IslandService) {
        self.owner = owner
        self.service = service
    }

    @discardableResult
    public func present(_ activity: IslandActivity) -> any IslandHandle {
        service.present(activity, owner: owner)
    }

    public func showHUD(_ hud: IslandHUD) {
        service.showHUD(hud, owner: owner)
    }

    public func dismissAll() {
        service.dismissAll(owner: owner)
    }

    public func setScrollHandler(_ handler: (@MainActor (IslandScrollEvent) -> Void)?) {
        service.setScrollHandler(handler, owner: owner)
    }
}
