import Foundation
import KKitCore
import KKitServicesAPI
import KKitServicesTesting
import Testing
@testable import FeatureSearch

@MainActor
private func lastBatch(_ stream: AsyncStream<[SearchResult]>) async -> [SearchResult] {
    var last: [SearchResult] = []
    for await batch in stream {
        last = batch
    }
    return last
}

struct WebQueryTests {
    @Test func detectsURLs() {
        #expect(WebQuery.detectURL("https://example.com/a?b=c")?.absoluteString == "https://example.com/a?b=c")
        #expect(WebQuery.detectURL("apple.com")?.absoluteString == "https://apple.com")
        #expect(WebQuery.detectURL("github.com/kuberrr0/KKit")?.absoluteString == "https://github.com/kuberrr0/KKit")
        #expect(WebQuery.detectURL("bbc.co.uk")?.absoluteString == "https://bbc.co.uk")
        #expect(WebQuery.detectURL("localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(WebQuery.detectURL("192.168.1.1:8080/admin")?.absoluteString == "http://192.168.1.1:8080/admin")
    }

    @Test func ignoresThingsThatAreNotURLs() {
        #expect(WebQuery.detectURL("1.5") == nil)
        #expect(WebQuery.detectURL("v1.2.3") == nil)
        #expect(WebQuery.detectURL("readme.md") == nil)
        #expect(WebQuery.detectURL("notes.txt") == nil)
        #expect(WebQuery.detectURL("night shift") == nil)
        #expect(WebQuery.detectURL("e.g") == nil)
        #expect(WebQuery.detectURL("localhost:abc") == nil)
        #expect(WebQuery.detectURL("/usr/bin") == nil)
    }

    @Test func parsesKeywordSearches() {
        let parsed = WebQuery.parse("yt lofi beats")
        guard case .keyword(let engine, let text) = parsed else {
            Issue.record("Expected a keyword search, got \(String(describing: parsed))")
            return
        }
        #expect(engine.id == "youtube")
        #expect(text == "lofi beats")
        #expect(WebQuery.parse("cats and dogs") == .text("cats and dogs"))
        #expect(WebQuery.parse("   ") == nil)
    }

    @Test func encodesSearches() {
        let url = SearchEngine.engine(id: "google").url(for: "a&b c+d")
        #expect(url?.absoluteString == "https://www.google.com/search?q=a%26b%20c%2Bd")
        #expect(SearchEngine.engine(id: "missing").id == "google")
    }
}

@MainActor
struct WebProviderTests {
    private let environment = TestEnvironment()

    private func makeProvider() -> WebProvider {
        let settings = FeatureSettings(featureID: "search", store: environment.settings)
        settings[SearchSettings.bookmarks] = false
        return WebProvider(settings: settings, bookmarks: BookmarkIndex())
    }

    @Test func rootSearchEndsWithAFallback() async {
        let results = await lastBatch(makeProvider().results(for: SearchQuery(text: "swift actors")))
        #expect(results.count == 1)
        #expect(results.first?.isFallback == true)
        #expect(results.first?.title == "Search Google for “swift actors”")
    }

    @Test func scopedSearchListsEveryEngine() async {
        let results = await lastBatch(makeProvider().results(for: SearchQuery(text: "swift", isScoped: true)))
        #expect(results.count == SearchEngine.all.count)
        #expect(results.first?.accessory == "Google")
        let noFallbacks = results.allSatisfy { !$0.isFallback }
        #expect(noFallbacks)
    }

    @Test func typedURLsOpenDirectly() async {
        let results = await lastBatch(makeProvider().results(for: SearchQuery(text: "apple.com")))
        #expect(results.first?.kind == .url(URL(string: "https://apple.com")!))
        #expect(results.first?.title == "Open apple.com")
    }

    @Test func bookmarksMatchTitleAndHost() {
        let options = WebOptions(defaultEngine: SearchEngine.all[0], scoped: false, fallback: true, browser: nil)
        let bookmarks = [
            Bookmark(title: "Hacker News", url: URL(string: "https://news.ycombinator.com")!, source: "Chrome"),
            Bookmark(title: "Swift Forums", url: URL(string: "https://forums.swift.org")!, source: "Safari"),
        ]
        let results = WebProvider.bookmarkResults("hacker", in: bookmarks, options: options)
        #expect(results.map(\.title) == ["Hacker News"])
        #expect(results.first?.accessory == "Chrome")
    }
}

struct BookmarkParsingTests {
    @Test func readsChromiumBookmarks() throws {
        let json = """
        {"roots": {"bookmark_bar": {"type": "folder", "children": [
            {"type": "url", "name": "KKit", "url": "https://github.com/kuberrr0/KKit"},
            {"type": "folder", "name": "Dev", "children": [
                {"type": "url", "name": "Swift", "url": "https://swift.org"},
                {"type": "url", "name": "Local", "url": "file:///tmp"}
            ]}
        ]}, "other": {"type": "folder", "children": []}}}
        """
        let bookmarks = BookmarkIndex.parseChromium(Data(json.utf8), source: "Chrome")
        #expect(Set(bookmarks.map(\.title)) == ["KKit", "Swift"])
    }

    @Test func readsSafariBookmarks() throws {
        let plist: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://apple.com", "URIDictionary": ["title": "Apple"]],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        #expect(BookmarkIndex.parseSafari(data).map(\.title) == ["Apple"])
    }
}

struct AppsProviderTests {
    private let apps = [
        AppEntry(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari", bundleID: "com.apple.Safari", keywords: []),
        AppEntry(url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", keywords: []),
        AppEntry(url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), name: "Terminal", bundleID: "com.apple.Terminal", keywords: []),
    ]

    @Test func matchesByPrefixAndInitials() {
        #expect(AppsProvider.match("saf", in: apps).first?.title == "Safari")
        #expect(AppsProvider.match("vsc", in: apps).first?.title == "Visual Studio Code")
        #expect(AppsProvider.match("zzz", in: apps).isEmpty)
    }

    @Test func resultsOpenTheApp() {
        let result = AppsProvider.match("term", in: apps).first
        #expect(result?.id == "app:com.apple.Terminal")
        #expect(result?.kind == .application(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")))
        #expect(result?.subtitle == "/System/Applications/Utilities")
    }

    @Test func scansFoldersOneLevelDeep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppIndexTests-\(UUID().uuidString)")
        let utilities = root.appendingPathComponent("Utilities")
        try FileManager.default.createDirectory(at: utilities.appendingPathComponent("Tool.app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Editor.app"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let names = AppIndex.scan(roots: [root], extras: []).map(\.name).sorted()
        #expect(names == ["Editor", "Tool"])
    }
}

@MainActor
struct FilesProviderTests {
    private let environment = TestEnvironment()

    private func makeProvider() -> FilesProvider {
        let fileSearch = environment.fileSearch
        fileSearch.files = [
            FileSearchHit(url: URL(fileURLWithPath: "/Users/kv/Documents/Report.pdf"), name: "Report.pdf", isDirectory: false),
            FileSearchHit(url: URL(fileURLWithPath: "/Users/kv/Code/report-tool"), name: "report-tool", isDirectory: true),
        ]
        return FilesProvider(search: { fileSearch }, settings: FeatureSettings(featureID: "search", store: environment.settings))
    }

    @Test func rootSearchNeedsThreeLetters() async {
        let provider = makeProvider()
        let short = await lastBatch(provider.results(for: SearchQuery(text: "re")))
        #expect(short.isEmpty)
        #expect(environment.fileSearch.searches.isEmpty)
        let results = await lastBatch(provider.results(for: SearchQuery(text: "report")))
        #expect(results.count == 2)
        let belowApps = results.allSatisfy { $0.score < 0.7 }
        #expect(belowApps)
    }

    @Test func scopedSearchShowsFolders() async {
        let results = await lastBatch(makeProvider().results(for: SearchQuery(text: "tool", isScoped: true)))
        #expect(results.map(\.title) == ["report-tool"])
        #expect(results.first?.accessory == "Folder")
        #expect(results.first?.kind == .file(URL(fileURLWithPath: "/Users/kv/Code/report-tool")))
    }

    @Test func canStayOutOfRootSearch() {
        let provider = makeProvider()
        #expect(provider.includeInRootSearch)
        FeatureSettings(featureID: "search", store: environment.settings)[SearchSettings.filesInRoot] = false
        #expect(!provider.includeInRootSearch)
    }
}

struct SystemSettingsProviderTests {
    @Test func findsPanesByNameAndKeyword() {
        let panes = SystemSettingsPane.all
        #expect(SystemSettingsProvider.match("bluet", scoped: false, in: panes).first?.title == "Bluetooth")
        #expect(SystemSettingsProvider.match("dark mode", scoped: false, in: panes).first?.title == "Appearance")
        let screenRecording = SystemSettingsProvider.match("screen recording", scoped: true, in: panes).first
        #expect(screenRecording?.subtitle == "System Settings › Privacy & Security")
    }

    @Test func prefixAloneListsEverything() {
        let panes = SystemSettingsPane.all
        #expect(SystemSettingsProvider.match("", scoped: true, in: panes).count == panes.count)
        #expect(SystemSettingsProvider.match("", scoped: false, in: panes).isEmpty)
    }

    @Test func paneIDsAreUnique() {
        let ids = SystemSettingsPane.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

@MainActor
struct SearchFeatureTests {
    @Test func commandsOpenTheBarWithAPrefix() async throws {
        let environment = TestEnvironment()
        let feature = SearchFeature(context: environment.makeContext(for: "search"))
        let found: Command? = feature.commands.first { $0.id == "search.files" }
        let command = try #require(found)
        try await command.perform(CommandInvocation())
        #expect(environment.floatingBar.shownQueries == ["f "])
        let providerIDs = feature.searchProviders.map(\.id)
        #expect(providerIDs == ["apps", "files", "systemSettings", "web"])
    }
}
