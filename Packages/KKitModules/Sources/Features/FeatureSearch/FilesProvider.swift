import Foundation
import KKitCore
import KKitServicesAPI

/// Files and folders from Spotlight, searched through the whole home folder. `f ` lists
/// up to 30 in the service's order (exact names and shallow paths first); root search
/// asks Spotlight only for three or more letters and shows a few, below apps and
/// commands. When macOS still hides Desktop, Documents or Downloads from KKit, `f `
/// ends with a row that opens the setting.
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
        let service = search()
        let hits = service.search(text, limit: scoped ? 30 : 12)
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await batch in hits {
                    var results = Self.results(for: batch, query: text, scoped: scoped)
                    if scoped, let access = Self.accessResult(blocked: service.blockedFolders) {
                        results.append(access)
                    }
                    continuation.yield(results)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Scoped: everything, in the service's order. Root: only good name matches, scored
    /// below apps and commands.
    nonisolated static func results(for hits: [FileSearchHit], query: String, scoped: Bool) -> [SearchResult] {
        var results: [SearchResult] = []
        for (index, hit) in hits.enumerated() {
            let score: Double
            if scoped {
                score = 0.99 - 0.01 * Double(index)
            } else {
                let match = FuzzyMatch.score(query, in: hit.name)
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

    /// "Allow Access to Desktop and Downloads", opening Privacy & Security › Files and
    /// Folders, or `nil` when nothing is blocked.
    nonisolated static func accessResult(blocked: [String]) -> SearchResult? {
        guard !blocked.isEmpty,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        else { return nil }
        let folders = ListFormatter.localizedString(byJoining: blocked)
        return SearchResult(
            id: "files:access",
            title: String(localized: "Allow Access to \(folders)"),
            subtitle: String(localized: "macOS hides the files in them from KKit until you turn KKit on in Files and Folders"),
            icon: .symbol("lock"),
            score: 0,
            kind: .url(url),
            actionTitle: String(localized: "Open Settings"),
            isFallback: true
        )
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
