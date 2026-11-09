import SwiftUI

/// A section in the KKit menu bar popover, below the Quick Toggles grid
/// (volume slider, Night Shift slider, stats strip).
public struct MenuBarSection: Identifiable {
    /// Unique within the feature.
    public let id: String
    /// Lower comes first. Volume 100, Night Shift 200, Stats 900.
    public var order: Int
    public let makeView: @MainActor () -> AnyView

    public init<Content: View>(
        id: String,
        order: Int = 500,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.order = order
        self.makeView = { AnyView(content()) }
    }
}

/// A standalone status item in the menu bar (e.g. Stats' CPU graph), separate from
/// the KKit icon. The menu bar host creates the `NSStatusItem`, sizes it to the label,
/// and shows `popover` when it's clicked.
public struct MenuBarItem: Identifiable {
    /// Unique within the feature: "cpu", "network".
    public let id: String
    /// Shown in the status item's accessibility label and menus.
    public var title: String
    /// Whether the item is in the menu bar right now. Read inside observation
    /// tracking, so reading `@Observable` state or settings keeps it current.
    public let isVisible: @MainActor () -> Bool
    /// The label drawn in the menu bar. Keep it under ~22 pt tall.
    public let makeLabel: @MainActor () -> AnyView
    /// Shown in a popover when the item is clicked; `nil` for no popover.
    public let makePopover: (@MainActor () -> AnyView)?

    public init<Label: View>(
        id: String,
        title: String,
        isVisible: @escaping @MainActor () -> Bool = { true },
        @ViewBuilder label: @escaping @MainActor () -> Label
    ) {
        self.id = id
        self.title = title
        self.isVisible = isVisible
        self.makeLabel = { AnyView(label()) }
        self.makePopover = nil
    }

    public init<Label: View, Popover: View>(
        id: String,
        title: String,
        isVisible: @escaping @MainActor () -> Bool = { true },
        @ViewBuilder label: @escaping @MainActor () -> Label,
        @ViewBuilder popover: @escaping @MainActor () -> Popover
    ) {
        self.id = id
        self.title = title
        self.isVisible = isVisible
        self.makeLabel = { AnyView(label()) }
        self.makePopover = { AnyView(popover()) }
    }
}
