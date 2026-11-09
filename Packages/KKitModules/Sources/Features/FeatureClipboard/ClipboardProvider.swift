import Foundation
import KKitCore
import SwiftUI

/// `c ` in the Floating Bar: clipboard history and snippets. ↵ pastes into the app in
/// front. Results are `.custom`, so copied text never lands in the Floating Bar's
/// Favourites or Recent.
@MainActor
final class ClipboardProvider: SearchProvider {
    nonisolated static let itemPrefix = "clipboard:"
    nonisolated static let snippetPrefix = "snippet:"

    let id = "history"
    let displayName = String(localized: "Clipboard History")
    let symbol = "list.clipboard"
    let prefix: String? = "c "
    let includeInRootSearch = false
    private let controller: ClipboardController

    init(controller: ClipboardController) {
        self.controller = controller
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let text = query.trimmed
        let controller = controller
        return .task {
            let items = await controller.search(text, limit: 40)
            let snippets = controller.matchingSnippets(text).prefix(8)
            let snippetResults = snippets.map { match in
                Self.result(for: match.snippet, score: text.isEmpty ? 0.4 : match.score, controller: controller)
            }
            let itemResults = items.enumerated().map { index, item in
                Self.result(for: item, rank: index, controller: controller)
            }
            return snippetResults + itemResults
        }
    }

    static func result(for item: ClipboardItem, rank: Int, controller: ClipboardController) -> SearchResult {
        let subtitle = [item.sourceAppName, item.lastUsedAt.formatted(.relative(presentation: .named))]
            .compactMap { $0 }
            .joined(separator: " · ")
        let icon: ResultIcon
        switch item.kind {
        case .files:
            icon = item.fileURLs.first.map { .file($0) } ?? .symbol(item.kind.symbol)
        case .color:
            icon = .glyph("●")
        default:
            icon = .symbol(item.isPinned ? "pin.fill" : item.kind.symbol)
        }
        return SearchResult(
            id: itemPrefix + String(item.id),
            title: item.title,
            subtitle: subtitle,
            icon: icon,
            // Newest first: the host keeps provider order for equal scores.
            score: max(0.3, 0.9 - Double(rank) * 0.01),
            kind: .custom,
            accessory: item.kind.title,
            actionTitle: String(localized: "Paste"),
            perform: { await controller.paste(item) },
            preview: { AnyView(ClipboardPreview(item: item, imageURL: controller.imageURL(for: item))) }
        )
    }

    static func result(for snippet: Snippet, score: Double, controller: ClipboardController) -> SearchResult {
        SearchResult(
            id: snippetPrefix + snippet.id.uuidString,
            title: snippet.name,
            subtitle: snippet.text.replacingOccurrences(of: "\n", with: " "),
            icon: .symbol("text.badge.plus"),
            score: score,
            kind: .custom,
            accessory: snippet.keyword.isEmpty ? String(localized: "Snippet") : snippet.keyword,
            actionTitle: String(localized: "Paste"),
            perform: { await controller.pasteSnippet(snippet) }
        )
    }

    /// The history item a result stands for.
    nonisolated static func itemID(of result: SearchResult) -> Int64? {
        guard result.id.hasPrefix(itemPrefix) else { return nil }
        return Int64(result.id.dropFirst(itemPrefix.count))
    }
}
