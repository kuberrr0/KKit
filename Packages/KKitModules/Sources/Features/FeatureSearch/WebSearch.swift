import Foundation
import KKitCore

/// A search engine: "g cats" or "w cats" with Google as the default.
struct SearchEngine: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    /// Typed before the search: "g", "yt".
    let keyword: String
    /// `%s` is replaced by the encoded search.
    let template: String
    let symbol: String

    func url(for text: String) -> URL? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: WebQuery.queryAllowed) ?? text
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    static var all: [SearchEngine] {
        [
            SearchEngine(id: "google", name: "Google", keyword: "g", template: "https://www.google.com/search?q=%s", symbol: "magnifyingglass"),
            SearchEngine(id: "duckduckgo", name: "DuckDuckGo", keyword: "ddg", template: "https://duckduckgo.com/?q=%s", symbol: "magnifyingglass"),
            SearchEngine(id: "bing", name: "Bing", keyword: "bing", template: "https://www.bing.com/search?q=%s", symbol: "magnifyingglass"),
            SearchEngine(id: "kagi", name: "Kagi", keyword: "kagi", template: "https://kagi.com/search?q=%s", symbol: "magnifyingglass"),
            SearchEngine(id: "youtube", name: "YouTube", keyword: "yt", template: "https://www.youtube.com/results?search_query=%s", symbol: "play.rectangle"),
            SearchEngine(id: "github", name: "GitHub", keyword: "gh", template: "https://github.com/search?q=%s", symbol: "chevron.left.forwardslash.chevron.right"),
            SearchEngine(id: "wikipedia", name: "Wikipedia", keyword: "wiki", template: "https://en.wikipedia.org/w/index.php?search=%s", symbol: "book"),
            SearchEngine(id: "stackoverflow", name: "Stack Overflow", keyword: "so", template: "https://stackoverflow.com/search?q=%s", symbol: "questionmark.bubble"),
            SearchEngine(id: "maps", name: "Apple Maps", keyword: "maps", template: "https://maps.apple.com/?q=%s", symbol: "map"),
        ]
    }

    static func engine(id: String) -> SearchEngine {
        all.first { $0.id == id } ?? all[0]
    }
}

/// What a web query is: a URL to open, a keyword search ("yt lofi"), or plain text.
enum WebQuery: Equatable {
    case url(URL)
    case keyword(SearchEngine, String)
    case text(String)

    /// Query characters, minus the ones that split a query string.
    static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return allowed
    }()

    static func parse(_ raw: String, engines: [SearchEngine] = SearchEngine.all) -> WebQuery? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = detectURL(text) {
            return .url(url)
        }
        if let space = text.firstIndex(of: " ") {
            let keyword = text[..<space].lowercased()
            let rest = text[space...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty, let engine = engines.first(where: { $0.keyword == keyword }) {
                return .keyword(engine, rest)
            }
        }
        return .text(text)
    }

    /// "https://x.y", "apple.com", "apple.com/mac", "localhost:3000", "192.168.1.1:8080".
    /// Not "1.5", "v1.2.3", "file.txt" or anything with spaces.
    static func detectURL(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
            return url
        }
        guard !text.contains("://"), !text.hasPrefix("/"), !text.hasPrefix(".") else { return nil }
        let hostPart = String(text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let host = String(hostPart.split(separator: ":", maxSplits: 1)[0]).lowercased()
        let port = hostPart.split(separator: ":", maxSplits: 1).dropFirst().first
        if let port, Int(port) == nil {
            return nil
        }
        let isLocal = host == "localhost" || isIPv4(host)
        guard isLocal || isDomain(host) else { return nil }
        return URL(string: (isLocal ? "http://" : "https://") + text)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }

    /// Labels of letters, digits and hyphens, and a top-level domain that's a known one or
    /// a two-letter country code that isn't also a common file extension.
    private static func isDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard labels.allSatisfy({ $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return false }
        guard let tld = labels.last, (2...24).contains(tld.count), tld.allSatisfy(\.isLetter) else { return false }
        let suffix = String(tld)
        return knownTLDs.contains(suffix) || (suffix.count == 2 && !fileExtensions.contains(suffix))
    }

    /// Two-letter file extensions that are also country domains: "readme.md" isn't a site.
    static let fileExtensions: Set<String> = [
        "md", "js", "py", "rb", "sh", "ts", "go", "rs", "cs", "pl", "el", "hs", "ml", "mm",
        "cc", "kt", "ps", "gz", "xz", "7z", "db", "so", "ai",
    ]

    /// Common generic top-level domains (every two-letter one is a country).
    static let knownTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "dev", "app", "io",
        "ai", "co", "me", "tv", "xyz", "site", "online", "tech", "store", "shop", "blog",
        "cloud", "page", "news", "art", "design", "wiki", "museum", "travel", "local",
        "test", "email", "link", "live", "studio", "social", "zone", "space", "systems",
    ]
}

/// A bookmark from a browser's bookmarks file.
struct Bookmark: Sendable, Hashable {
    let title: String
    let url: URL
    /// "Chrome", "Safari".
    let source: String
}

/// Bookmarks from Chromium-family browsers (their `Bookmarks` JSON) and Safari (its
/// plist, readable only with Full Disk Access). Read once, then again after ten minutes.
actor BookmarkIndex {
    private var bookmarks: [Bookmark] = []
    private var loadedAt: Date?
    private let maxAge: TimeInterval = 600

    func all() -> [Bookmark] {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < maxAge {
            return bookmarks
        }
        bookmarks = Self.load()
        loadedAt = Date()
        return bookmarks
    }

    static func load() -> [Bookmark] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        let chromium: [(String, String)] = [
            ("Chrome", "Google/Chrome"),
            ("Brave", "BraveSoftware/Brave-Browser"),
            ("Edge", "Microsoft Edge"),
            ("Vivaldi", "Vivaldi"),
            ("Chromium", "Chromium"),
        ]
        var result: [Bookmark] = []
        for (name, folder) in chromium {
            let file = support.appendingPathComponent(folder).appendingPathComponent("Default/Bookmarks")
            if let data = try? Data(contentsOf: file) {
                result.append(contentsOf: parseChromium(data, source: name))
            }
        }
        let safari = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
        if let data = try? Data(contentsOf: safari) {
            result.append(contentsOf: parseSafari(data))
        }
        var seen = Set<URL>()
        return result.filter { seen.insert($0.url).inserted }
    }

    /// `{"roots": {"bookmark_bar": {"children": [{"type": "url", "name", "url"}, {"type": "folder", "children"}]}}}`
    static func parseChromium(_ data: Data, source: String) -> [Bookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }
        var result: [Bookmark] = []
        func walk(_ node: [String: Any]) {
            if node["type"] as? String == "url",
               let name = node["name"] as? String,
               let string = node["url"] as? String,
               let url = URL(string: string),
               url.scheme == "http" || url.scheme == "https" {
                result.append(Bookmark(title: name.isEmpty ? string : name, url: url, source: source))
            }
            for child in node["children"] as? [[String: Any]] ?? [] {
                walk(child)
            }
        }
        for case let root as [String: Any] in roots.values {
            walk(root)
        }
        return result
    }

    /// `WebBookmarkTypeLeaf` entries with `URLString` and `URIDictionary.title`.
    static func parseSafari(_ data: Data) -> [Bookmark] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return []
        }
        var result: [Bookmark] = []
        func walk(_ node: [String: Any]) {
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
               let string = node["URLString"] as? String,
               let url = URL(string: string),
               url.scheme == "http" || url.scheme == "https" {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
                result.append(Bookmark(title: title ?? string, url: url, source: "Safari"))
            }
            for child in node["Children"] as? [[String: Any]] ?? [] {
                walk(child)
            }
        }
        walk(plist)
        return result
    }
}
