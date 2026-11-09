import SwiftUI

/// A page in the expanded Island (Stats, Timer, Privacy…). Pages sit next to the
/// expanded views of live activities; the Island host shows them with a page picker.
public struct IslandPage: Identifiable {
    /// Unique within the feature: "stats", "timer".
    public let id: String
    public var title: String
    public var symbol: String
    public let makeView: @MainActor () -> AnyView

    public init<Content: View>(
        id: String,
        title: String,
        symbol: String,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.makeView = { AnyView(content()) }
    }
}
