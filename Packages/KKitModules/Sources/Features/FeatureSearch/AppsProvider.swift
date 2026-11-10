import Foundation
import KKitCore
import os

/// An installed application.
struct AppEntry: Sendable, Hashable {
    let url: URL
    /// As Finder shows it, localized, without ".app".
    let name: String
    let bundleID: String?
    /// Other names it's found by: the file name when the display name differs.
    let keywords: [String]

    var resultID: String { "app:\(bundleID ?? url.path)" }
}

/// The installed applications, scanned off the main thread and kept for ten minutes.
/// A search that finds the list older than that gets the old list straight away and
/// starts a rescan.
actor AppIndex {
    static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        ]
    }

    static var extraApps: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    }

    private let roots: [URL]
    private let extras: [URL]
    private let maxAge: TimeInterval
    private let log: Logger?
    private var entries: [AppEntry] = []
    private var scannedAt: Date?
    private var scanTask: Task<[AppEntry], Never>?

    init(
        roots: [URL] = AppIndex.defaultRoots,
        extras: [URL] = AppIndex.extraApps,
        maxAge: TimeInterval = 600,
        log: Logger? = nil
    ) {
        self.roots = roots
        self.extras = extras
        self.maxAge = maxAge
        self.log = log
    }

    func apps() async -> [AppEntry] {
        guard let scannedAt else {
            return await rescan()
        }
        if Date().timeIntervalSince(scannedAt) > maxAge, scanTask == nil {
            Task { await self.rescan() }
        }
        return entries
    }

    @discardableResult
    func rescan() async -> [AppEntry] {
        if let scanTask {
            return await scanTask.value
        }
        let roots = roots
        let extras = extras
        let task = Task.detached(priority: .utility) {
            AppIndex.scan(roots: roots, extras: extras)
        }
        scanTask = task
        let started = Date()
        let result = await task.value
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        if result.isEmpty {
            log?.error("Found no applications in \(roots.map(\.path).joined(separator: ", "), privacy: .public)")
        } else {
            log?.info("Indexed \(result.count) applications in \(milliseconds) ms")
        }
        entries = result
        scannedAt = Date()
        scanTask = nil
        return result
    }

    /// Apps in each root and one folder down (/Applications/Utilities), deduplicated by
    /// bundle ID with the first root winning.
    nonisolated static func scan(roots: [URL], extras: [URL]) -> [AppEntry] {
        let manager = FileManager.default
        var found: [URL] = []
        for root in roots {
            guard let children = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    found.append(child)
                } else if isPlainFolder(child), let nested = try? manager.contentsOfDirectory(
                    at: child,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) {
                    found.append(contentsOf: nested.filter { $0.pathExtension == "app" })
                }
            }
        }
        found.append(contentsOf: extras.filter { manager.fileExists(atPath: $0.path) })

        var seen = Set<String>()
        var entries: [AppEntry] = []
        for url in found {
            let entry = makeEntry(url)
            let key = entry.bundleID ?? url.path
            guard seen.insert(key).inserted else { continue }
            entries.append(entry)
        }
        return entries
    }

    nonisolated static func makeEntry(_ url: URL) -> AppEntry {
        let fileName = url.deletingPathExtension().lastPathComponent
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        if name.isEmpty {
            name = fileName
        }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let keywords = name == fileName ? [] : [fileName]
        return AppEntry(url: url, name: name, bundleID: bundleID, keywords: keywords)
    }

    private nonisolated static func isPlainFolder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        return values.isDirectory == true && values.isPackage != true
    }
}

/// Applications: in root search, and all of them, A to Z, under `a `.
@MainActor
final class AppsProvider: SearchProvider {
    nonisolated static let prefixText = "a "

    let id = "apps"
    let displayName = String(localized: "Applications")
    let symbol = "square.grid.2x2"
    let prefix: String? = AppsProvider.prefixText
    private let index: AppIndex

    init(index: AppIndex) {
        self.index = index
    }

    func warmUp() {
        let index = index
        Task.detached(priority: .utility) {
            _ = await index.apps()
        }
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let text = query.trimmed
        let scoped = query.isScoped
        guard scoped || !text.isEmpty else { return .single([]) }
        let index = index
        return .task {
            let apps = await index.apps()
            if text.isEmpty {
                return Self.all(apps)
            }
            return Self.match(text, in: apps, limit: scoped ? 60 : 8)
        }
    }

    nonisolated static func match(_ text: String, in apps: [AppEntry], limit: Int = 8) -> [SearchResult] {
        var scored: [(AppEntry, Double)] = []
        for app in apps {
            guard let score = FuzzyMatch.score(text, title: app.name, keywords: app.keywords), score >= 0.35 else {
                continue
            }
            scored.append((app, score))
        }
        scored.sort { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.name.count < $1.0.name.count) }
        return scored.prefix(limit).map { result(for: $0, score: $1) }
    }

    /// Every app, by name (`a ` with nothing after it). They all score the same, so the
    /// Floating Bar keeps this order apart from frecency.
    nonisolated static func all(_ apps: [AppEntry]) -> [SearchResult] {
        apps
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { result(for: $0, score: 0.5) }
    }

    nonisolated static func result(for entry: AppEntry, score: Double) -> SearchResult {
        SearchResult(
            id: entry.resultID,
            title: entry.name,
            subtitle: folderName(of: entry.url),
            icon: .file(entry.url),
            score: score,
            kind: .application(entry.url),
            accessory: String(localized: "Application"),
            actionTitle: String(localized: "Open")
        )
    }

    nonisolated static func folderName(of url: URL) -> String {
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent.hasPrefix(home) {
            return "~" + parent.dropFirst(home.count)
        }
        return parent
    }
}
