import Foundation
import KKitCore
import UniformTypeIdentifiers

/// One thing on the Shelf.
struct ShelfItem: Codable, Identifiable, Hashable, Sendable {
    enum Content: Codable, Hashable, Sendable {
        case file(URL)
        case text(String)
        case link(URL)
    }

    var id: UUID
    var content: Content
    var addedAt: Date
    /// The file is the Shelf's own copy (kept in its folder), deleted when the item is
    /// removed. Otherwise it's the user's file, which the Shelf only points to.
    var isOwnCopy: Bool

    init(id: UUID = UUID(), content: Content, addedAt: Date, isOwnCopy: Bool = false) {
        self.id = id
        self.content = content
        self.addedAt = addedAt
        self.isOwnCopy = isOwnCopy
    }

    var fileURL: URL? {
        if case .file(let url) = content { url } else { nil }
    }

    var title: String {
        switch content {
        case .file(let url): url.lastPathComponent
        case .text(let text): ShelfItem.firstLine(of: text)
        case .link(let url): url.host() ?? url.absoluteString
        }
    }

    var subtitle: String? {
        switch content {
        case .file(let url): url.deletingLastPathComponent().path
        case .text(let text): String(localized: "\(text.count) characters")
        case .link(let url): url.absoluteString
        }
    }

    var symbol: String {
        switch content {
        case .file: isImage ? "photo" : isPDF ? "doc.richtext" : "doc"
        case .text: "text.alignleft"
        case .link: "link"
        }
    }

    var contentType: UTType? {
        guard let url = fileURL else { return nil }
        return UTType(filenameExtension: url.pathExtension)
    }

    var isText: Bool {
        if case .text = content { true } else { false }
    }

    var isImage: Bool { contentType?.conforms(to: .image) == true }
    var isPDF: Bool { contentType?.conforms(to: .pdf) == true }
    var isFolder: Bool {
        guard let url = fileURL else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// The text that "Copy" puts on the clipboard for text and links.
    var plainText: String? {
        switch content {
        case .file: nil
        case .text(let text): text
        case .link(let url): url.absoluteString
        }
    }

    static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
    }
}

enum ShelfAutoClear: Int, Codable, Sendable, CaseIterable, Identifiable {
    case never = 0
    case hour = 1
    case sixHours = 6
    case day = 24
    case threeDays = 72

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .hour: String(localized: "After an hour")
        case .sixHours: String(localized: "After 6 hours")
        case .day: String(localized: "After a day")
        case .threeDays: String(localized: "After 3 days")
        }
    }

    var interval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue) * 3600
    }
}

enum ShelfSettings {
    /// Copy dropped files into the Shelf's folder instead of pointing to them.
    static let keepCopies = SettingKey("keepCopies", default: false)
    static let autoClear = SettingKey("autoClear", default: ShelfAutoClear.never)
    static let maxItems = SettingKey("maxItems", default: 50)
    /// Expand the Island on the Shelf after something is dropped on it.
    static let showAfterDrop = SettingKey("showAfterDrop", default: true)
}

enum ShelfError: LocalizedError {
    case nameTaken(String)
    case invalidName
    case notAnImage
    case needsTwoPDFs
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .nameTaken(let name): String(localized: "There's already a file called “\(name)”.")
        case .invalidName: String(localized: "That name can't be used.")
        case .notAnImage: String(localized: "Only images can be converted.")
        case .needsTwoPDFs: String(localized: "Put at least two PDFs on the Shelf to merge them.")
        case .failed(let message): message
        }
    }
}
