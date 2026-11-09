import AppKit
import KKitCore

/// How web results are made, from the query and the settings.
struct WebOptions: Sendable {
    var defaultEngine: SearchEngine
    var scoped: Bool
    var fallback: Bool
    var browser: URL?
}

/// URLs, search engines and bookmarks. In root search: a typed URL, a keyword search
/// ("yt lofi"), matching bookmarks, and "Search Google for …" as the last row.
@MainActor
final class WebProvider: SearchProvider {
    static let prefixText = "w "

    let id = "web"
    let displayName = String(localized: "Web")
    let symbol = "globe"
    let prefix: String? = WebProvider.prefixText
    private let settings: FeatureSettings
    private let bookmarks: BookmarkIndex

    init(settings: FeatureSettings, bookmarks: BookmarkIndex) {
        self.settings = settings
        self.bookmarks = bookmarks
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let text = query.trimmed
        guard !text.isEmpty else { return .single([]) }
        let options = WebOptions(
            defaultEngine: SearchEngine.engine(id: settings[SearchSettings.defaultEngine]),
            scoped: query.isScoped,
            fallback: settings[SearchSettings.webFallback],
            browser: browserURL
        )
        let immediate = Self.results(for: text, options: options)
        guard settings[SearchSettings.bookmarks], text.count >= 2 else { return .single(immediate) }
        let bookmarks = bookmarks
        return AsyncStream { continuation in
            continuation.yield(immediate)
            let task = Task { @MainActor in
                let all = await bookmarks.all()
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                let matches = Self.bookmarkResults(text, in: all, options: options)
                if !matches.isEmpty {
                    continuation.yield(immediate + matches)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Opens a search with the default engine (the "Search the Web for This" action).
    func searchDefaultEngine(for text: String) {
        let engine = SearchEngine.engine(id: settings[SearchSettings.defaultEngine])
        guard let url = engine.url(for: text) else { return }
        Self.openURL(url, browser: browserURL)
    }

    // MARK: Results

    nonisolated static func results(for text: String, options: WebOptions) -> [SearchResult] {
        guard let parsed = WebQuery.parse(text) else { return [] }
        switch parsed {
        case .url(let url):
            return [urlResult(url, options: options)]
        case .keyword(let engine, let search):
            return [searchResult(engine, search, score: 0.95, options: options)]
        case .text(let search):
            if options.scoped {
                // The default engine first, then the others.
                let others = SearchEngine.all.filter { $0.id != options.defaultEngine.id }
                return [searchResult(options.defaultEngine, search, score: 0.9, options: options)]
                    + others.map { searchResult($0, search, score: 0.4, options: options) }
            }
            guard options.fallback else { return [] }
            var fallback = searchResult(options.defaultEngine, search, score: 0, options: options)
            fallback.isFallback = true
            return [fallback]
        }
    }

    nonisolated static func urlResult(_ url: URL, options: WebOptions) -> SearchResult {
        let display = url.host.map { host in
            url.path.isEmpty || url.path == "/" ? host : host + url.path
        } ?? url.absoluteString
        return SearchResult(
            id: "url:\(url.absoluteString)",
            title: String(localized: "Open \(display)"),
            subtitle: url.absoluteString,
            icon: .symbol("safari"),
            score: 0.96,
            kind: .url(url),
            actionTitle: String(localized: "Open"),
            perform: performer(url, browser: options.browser)
        )
    }

    nonisolated static func searchResult(_ engine: SearchEngine, _ text: String, score: Double, options: WebOptions) -> SearchResult {
        let url = engine.url(for: text) ?? URL(string: "https://www.google.com")!
        return SearchResult(
            id: "web:\(engine.id):\(text)",
            title: String(localized: "Search \(engine.name) for “\(text)”"),
            subtitle: engine.keyword + " " + text,
            icon: .symbol(engine.symbol),
            score: score,
            kind: .url(url),
            accessory: engine.name,
            actionTitle: String(localized: "Search"),
            perform: performer(url, browser: options.browser)
        )
    }

    nonisolated static func bookmarkResults(_ text: String, in bookmarks: [Bookmark], options: WebOptions) -> [SearchResult] {
        var results: [SearchResult] = []
        for bookmark in bookmarks {
            let host = bookmark.url.host ?? ""
            guard let match = FuzzyMatch.score(text, title: bookmark.title, keywords: [host]) else { continue }
            if !options.scoped, match < 0.7 {
                continue
            }
            results.append(SearchResult(
                id: "url:\(bookmark.url.absoluteString)",
                title: bookmark.title,
                subtitle: host,
                icon: .symbol("bookmark"),
                score: options.scoped ? match : match * 0.8,
                kind: .url(bookmark.url),
                accessory: bookmark.source,
                actionTitle: String(localized: "Open"),
                perform: performer(bookmark.url, browser: options.browser)
            ))
        }
        results.sort { $0.score > $1.score }
        return Array(results.prefix(options.scoped ? 20 : 3))
    }

    // MARK: Opening

    /// The browser chosen in Settings, if it's still installed.
    private var browserURL: URL? {
        let path = settings[SearchSettings.browser]
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// `nil` (the host opens it in the default browser) unless a browser is chosen.
    nonisolated static func performer(_ url: URL, browser: URL?) -> SearchResult.Perform? {
        guard let browser else { return nil }
        return { WebProvider.openURL(url, browser: browser) }
    }

    static func openURL(_ url: URL, browser: URL?) {
        guard let browser else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// Apps that open web links, for Settings.
    static func browsers() -> [URL] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
    }
}
