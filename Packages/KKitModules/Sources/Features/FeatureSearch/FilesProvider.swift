import Foundation
import KKitCore
import KKitServicesAPI

/// Files and folders from Spotlight. `f ` lists up to 30; root search asks Spotlight
/// only for three or more letters and shows a few, below apps and commands.
@MainActor
final class FilesProvider: SearchProvider {
    nonisolated static let prefixText = "f "

    let id = "files"
    let displayName = String(localized: "Files & Folders")
    let symbol = "doc"
    let prefix: String? = FilesProvider.prefixText
    private let search: @MainActor () -> any FileSearchService
    private let settings: FeatureSettings

    init(search: @escaping @MainActor () -> any FileSearchService, settings: FeatureSettings) {
        self.search = search
        self.settings = settings
    }

    var includeInRootSearch: Bool {
        settings[SearchSettings.filesInRoot]
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let text = query.trimmed
        let scoped = query.isScoped
        guard scoped ? !text.isEmpty : text.count >= 3 else { return .single([]) }
        let hits = search().search(text, limit: scoped ? 30 : 12)
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await batch in hits {
                    continuation.yield(Self.results(for: batch, query: text, scoped: scoped))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Scoped: everything, by match then by last use (Spotlight's order). Root: only good
    /// name matches, scored below apps and commands.
    nonisolated static func results(for hits: [FileSearchHit], query: String, scoped: Bool) -> [SearchResult] {
        var results: [SearchResult] = []
        for hit in hits {
            let match = FuzzyMatch.score(query, in: hit.name)
            let score: Double
            if scoped {
                score = 0.5 + 0.5 * (match ?? 0.3)
            } else {
                guard let match, match >= 0.6 else { continue }
                score = match * 0.7
            }
            results.append(result(for: hit, score: score))
            if !scoped, results.count == 4 {
                break
            }
        }
        return results
    }

    nonisolated static func result(for hit: FileSearchHit, score: Double) -> SearchResult {
        SearchResult(
            id: "file:\(hit.url.path)",
            title: hit.name,
            subtitle: abbreviate(hit.url.deletingLastPathComponent().path),
            icon: .file(hit.url),
            score: score,
            kind: .file(hit.url),
            accessory: hit.isDirectory ? String(localized: "Folder") : nil,
            actionTitle: String(localized: "Open")
        )
    }

    /// "/Users/kv/Documents" → "~/Documents".
    nonisolated static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
