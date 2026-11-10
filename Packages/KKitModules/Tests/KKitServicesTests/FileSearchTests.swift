import Foundation
import KKitServicesAPI
import Testing
@testable import KKitServices

@MainActor
struct SpotlightRankingTests {
    private func hit(_ path: String, lastUsed: Date? = nil) -> FileSearchHit {
        let url = URL(fileURLWithPath: path)
        return FileSearchHit(url: url, name: url.lastPathComponent, isDirectory: false, lastUsed: lastUsed)
    }

    @Test func exactNamesAndShallowPathsComeFirst() {
        let hits = [
            hit("/Users/kv/Movies/CacheClip/audio/Users/kv/Downloads"),
            hit("/Users/kv/Documents/old downloads list.txt", lastUsed: .now),
            hit("/Users/kv/Downloads"),
            hit("/Users/kv/Documents/Downloads Archive"),
        ]
        let ranked = SpotlightSearch.rank(hits, query: "downloads").map(\.url.path)
        #expect(ranked == [
            "/Users/kv/Downloads",
            "/Users/kv/Movies/CacheClip/audio/Users/kv/Downloads",
            "/Users/kv/Documents/Downloads Archive",
            "/Users/kv/Documents/old downloads list.txt",
        ])
    }

    @Test func recentlyUsedBreaksTies() {
        let hits = [
            hit("/Users/kv/a/report.pdf", lastUsed: Date(timeIntervalSince1970: 1)),
            hit("/Users/kv/b/report.pdf", lastUsed: Date(timeIntervalSince1970: 2)),
        ]
        #expect(SpotlightSearch.rank(hits, query: "report").first?.url.path == "/Users/kv/b/report.pdf")
    }

    @Test func standardFoldersMatchByName() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("kkit-home-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home + "/Downloads", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let found = SpotlightSearch.standardFolders(matching: ["down"], home: home)
        #expect(found.map(\.name) == ["Downloads"])
        #expect(found.first?.isDirectory == true)
        // Folders that don't exist aren't offered.
        #expect(SpotlightSearch.standardFolders(matching: ["music"], home: home).isEmpty)
    }

    @Test func splitsAndCleansTheQuery() {
        #expect(SpotlightSearch.words(in: "  tax  re*turn ") == ["tax", "return"])
        #expect(SpotlightSearch.words(in: "\"*\"").isEmpty)
    }

    @Test func skipsHiddenFilesAppsAndLibrary() {
        let home = "/Users/kv"
        #expect(SpotlightSearch.isInteresting("/Users/kv/Documents/a.txt", home: home))
        #expect(!SpotlightSearch.isInteresting("/Users/kv/.config/a.txt", home: home))
        #expect(!SpotlightSearch.isInteresting("/Users/kv/Applications/Thing.app", home: home))
        #expect(!SpotlightSearch.isInteresting("/Users/kv/Library/Caches/a", home: home))
        #expect(SpotlightSearch.isInteresting("/Users/kv/Library/Mobile Documents/com~apple~CloudDocs/a", home: home))
    }
}
