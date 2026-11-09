import CryptoKit
import Foundation
import KKitServicesAPI

/// What a history item holds.
enum ClipboardKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case text
    case richText
    case link
    case image
    case files
    case color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: String(localized: "Text")
        case .richText: String(localized: "Rich Text")
        case .link: String(localized: "Link")
        case .image: String(localized: "Image")
        case .files: String(localized: "Files")
        case .color: String(localized: "Colour")
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .link: "link"
        case .image: "photo"
        case .files: "doc.on.doc"
        case .color: "paintpalette"
        }
    }
}

/// Something about to be saved: what `ClipboardFilter` makes of a clipboard change.
struct ClipboardDraft: Sendable, Equatable {
    var kind: ClipboardKind
    /// The searchable, plain text: the text itself, the link, file paths, a colour's hex.
    var text: String
    var rtf: Data?
    var fileURLs: [URL] = []
    var imageData: Data?
    /// "public.png", "public.tiff".
    var imageType: String?
    var color: RGBAColor?
    var sourceBundleID: String?
    var sourceAppName: String?
    var date: Date

    /// Identifies the same content copied again, so it moves to the top instead of
    /// being saved twice.
    var contentHash: String {
        var hasher = SHA256()
        // Rich and plain copies of the same words are the same item.
        let family = kind == .richText ? ClipboardKind.text : kind
        hasher.update(data: Data(family.rawValue.utf8))
        switch kind {
        case .image:
            hasher.update(data: imageData ?? Data())
        case .files:
            hasher.update(data: Data(fileURLs.map(\.path).joined(separator: "\n").utf8))
        case .color:
            hasher.update(data: Data((color?.hex ?? text).utf8))
        case .text, .richText, .link:
            hasher.update(data: Data(text.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One saved item.
struct ClipboardItem: Identifiable, Sendable, Hashable {
    var id: Int64
    var kind: ClipboardKind
    var text: String
    var rtf: Data?
    var fileURLs: [URL]
    /// The image's file name in the history's `images` folder.
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var color: RGBAColor?
    var sourceBundleID: String?
    var sourceAppName: String?
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int
    var isPinned: Bool

    /// One line for lists.
    var title: String {
        switch kind {
        case .image:
            if let imageWidth, let imageHeight {
                return String(localized: "Image \(imageWidth) × \(imageHeight)")
            }
            return String(localized: "Image")
        case .files:
            let names = fileURLs.map(\.lastPathComponent)
            if names.count > 1 {
                return String(localized: "\(names[0]) and \(names.count - 1) more")
            }
            return names.first ?? text
        case .color:
            return color?.hex ?? text
        case .text, .richText, .link:
            let line = text
                .split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? text
            return line.count > 120 ? String(line.prefix(120)) + "…" : line
        }
    }

    var url: URL? {
        guard kind == .link else { return nil }
        return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var lineCount: Int {
        text.split(whereSeparator: \.isNewline).count
    }

    /// What goes back on the clipboard. `plain` drops formatting.
    func contents(imageData: Data?, plain: Bool) -> PasteboardContents {
        switch kind {
        case .text:
            return .text(text)
        case .richText:
            return plain ? .text(text) : PasteboardContents(string: text, rtf: rtf)
        case .link:
            return PasteboardContents(string: text, url: plain ? nil : url)
        case .image:
            return PasteboardContents(image: imageData, imageType: imageFile.map(Self.imageType(forFile:)) ?? "public.png")
        case .files:
            return plain
                ? .text(fileURLs.map(\.path).joined(separator: "\n"))
                : PasteboardContents(string: fileURLs.map(\.path).joined(separator: "\n"), fileURLs: fileURLs)
        case .color:
            return plain ? .text(color?.hex ?? text) : PasteboardContents(string: color?.hex ?? text, color: color)
        }
    }

    static func imageType(forFile name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": "public.png"
        case "jpg", "jpeg": "public.jpeg"
        default: "public.tiff"
        }
    }

    static func fileExtension(forImageType type: String?) -> String {
        switch type {
        case "public.png": "png"
        case "public.jpeg": "jpg"
        default: "tiff"
        }
    }
}
