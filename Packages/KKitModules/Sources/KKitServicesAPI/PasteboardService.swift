import Foundation

/// A colour, 0…1 per channel, in sRGB.
public struct RGBAColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#RRGGBB" (or "#RRGGBBAA" when not opaque).
    public var hex: String {
        func byte(_ value: Double) -> String {
            String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded()))
        }
        let base = "#" + byte(red) + byte(green) + byte(blue)
        return alpha < 1 ? base + byte(alpha) : base
    }

    /// Parses "#RGB", "#RRGGBB" and "#RRGGBBAA" (the "#" is optional).
    public init?(hex text: String) {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
        if hex.count == 8 {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }
}

/// What's on the clipboard, by representation. A copy usually has several: a web page
/// selection has rich text, HTML and plain text; a Finder copy has file URLs and names.
public struct PasteboardContents: Sendable, Hashable {
    public var string: String?
    /// RTF data.
    public var rtf: Data?
    public var html: String?
    /// PNG or TIFF data, as the app put it there.
    public var image: Data?
    /// "public.png", "public.tiff".
    public var imageType: String?
    public var fileURLs: [URL]
    /// A link (Safari's "Copy Link" puts a URL and its title).
    public var url: URL?
    public var color: RGBAColor?
    /// Every type identifier on the clipboard, including markers such as
    /// `org.nspasteboard.ConcealedType` that say "don't record this".
    public var types: [String]

    public init(
        string: String? = nil,
        rtf: Data? = nil,
        html: String? = nil,
        image: Data? = nil,
        imageType: String? = nil,
        fileURLs: [URL] = [],
        url: URL? = nil,
        color: RGBAColor? = nil,
        types: [String] = []
    ) {
        self.string = string
        self.rtf = rtf
        self.html = html
        self.image = image
        self.imageType = imageType
        self.fileURLs = fileURLs
        self.url = url
        self.color = color
        self.types = types
    }

    public var isEmpty: Bool {
        string == nil && rtf == nil && html == nil && image == nil && fileURLs.isEmpty && url == nil && color == nil
    }

    public static func text(_ string: String) -> PasteboardContents {
        PasteboardContents(string: string, types: ["public.utf8-plain-text"])
    }
}

/// A change to the general clipboard.
public struct PasteboardChange: Sendable, Hashable {
    public var changeCount: Int
    public var contents: PasteboardContents
    /// The app in front when the copy happened (or the one that marked itself with
    /// `org.nspasteboard.source`).
    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// KKit wrote it (pasting from history, Calculator's Copy).
    public var isFromKKit: Bool
    public var date: Date

    public init(
        changeCount: Int,
        contents: PasteboardContents,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        isFromKKit: Bool = false,
        date: Date = Date()
    ) {
        self.changeCount = changeCount
        self.contents = contents
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.isFromKKit = isFromKKit
        self.date = date
    }
}

public struct PasteError: LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public static let needsAccessibility = PasteError(String(localized: "Copied. Allow Accessibility for KKit to paste for you."))
}

/// The general clipboard: changes, reading, writing and pasting into the app in front.
/// DESIGN.md §3.7, ARCHITECTURE.md §7.
///
/// macOS has no clipboard change notification, so `changes()` polls `changeCount`
/// (cheap) only while something subscribes.
@MainActor
public protocol PasteboardService: AnyObject {
    var changeCount: Int { get }
    /// The current contents, then every change.
    func changes() -> AsyncStream<PasteboardChange>
    func read() -> PasteboardContents
    /// Replaces the clipboard. The change is marked as KKit's own.
    func write(_ contents: PasteboardContents)
    /// Sends ⌘V to the app in front, after a short wait for the Floating Bar or picker
    /// to give up focus. Throws `PasteError.needsAccessibility` without Accessibility.
    func paste() async throws
    /// Whether `paste()` can work (Accessibility is granted).
    var canPaste: Bool { get }
}

public extension PasteboardService {
    func copy(_ text: String) {
        write(.text(text))
    }

    /// Writes and pastes; if pasting isn't allowed the contents stay copied and the
    /// error says so.
    func paste(_ contents: PasteboardContents) async throws {
        write(contents)
        try await paste()
    }
}
