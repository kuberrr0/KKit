import Foundation

/// Something dragged onto the Island (or handed to the Shelf by another feature).
public enum DroppedItem: Sendable, Hashable {
    case file(URL)
    case url(URL)
    case text(String)
    /// Image data without a file (a browser image, a screenshot). `type` is a UTType
    /// identifier: "public.png", "public.tiff".
    case image(Data, type: String)

    public var kind: DropKind {
        switch self {
        case .file: .files
        case .url: .urls
        case .text: .text
        case .image: .images
        }
    }

    /// A short label for lists and VoiceOver.
    public var summary: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .url(let url): url.host() ?? url.absoluteString
        case .text(let text): String(text.prefix(60))
        case .image: String(localized: "Image")
        }
    }
}

/// What a drop zone takes.
public struct DropKind: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let files = DropKind(rawValue: 1 << 0)
    public static let urls = DropKind(rawValue: 1 << 1)
    public static let text = DropKind(rawValue: 1 << 2)
    public static let images = DropKind(rawValue: 1 << 3)
    public static let all: DropKind = [.files, .urls, .text, .images]
}

/// A target in the Island's drop area. While a file, link or text is dragged toward the
/// notch, the Island opens into one zone per running feature that offers one
/// (Shelf, AirDrop, Quick Note) and hands the dropped items to the zone under the cursor.
public struct IslandDropZone: Identifiable {
    public typealias Perform = @MainActor @Sendable ([DroppedItem]) async -> Void

    /// Unique within the feature: "shelf", "airDrop".
    public let id: String
    public var title: String
    public var symbol: String
    /// Lower comes first. Shelf 100, AirDrop 200, Quick Note 300.
    public var order: Int
    public var accepts: DropKind
    public let perform: Perform

    public init(
        id: String,
        title: String,
        symbol: String,
        order: Int = 500,
        accepts: DropKind = .all,
        perform: @escaping Perform
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.order = order
        self.accepts = accepts
        self.perform = perform
    }

    /// The items this zone takes, in order.
    public func accepted(_ items: [DroppedItem]) -> [DroppedItem] {
        items.filter { accepts.contains($0.kind) }
    }
}
