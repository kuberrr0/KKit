import Darwin
import Foundation
import KKitServicesAPI

/// File name search with `NSMetadataQuery` over the whole home folder. Each search is
/// its own query, started on the main run loop and stopped when its stream ends.
///
/// Spotlight leaves out everything KKit may not read, and Desktop, Documents and
/// Downloads are protected by macOS (Privacy & Security › Files and Folders). So each
/// search first opens those folders off the main thread: the first time, that shows
/// macOS's "KKit would like to access…" prompt; afterwards it tells us which are still
/// denied (`blockedFolders`).
@MainActor
public final class SpotlightFileSearchService: FileSearchService {
    public private(set) var blockedFolders: [String] = []
    private var isCheckingAccess = false

    public init() {}

    public func search(_ text: String, limit: Int) -> AsyncStream<[FileSearchHit]> {
        checkFolderAccess()
        let (stream, continuation) = AsyncStream.makeStream(
            of: [FileSearchHit].self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let search = SpotlightSearch(text: text, limit: limit, continuation: continuation)
        continuation.onTermination = { _ in
            Task { @MainActor in search.stop() }
        }
        search.start()
        return stream
    }

    private func checkFolderAccess() {
        guard !isCheckingAccess else { return }
        isCheckingAccess = true
        Task.detached(priority: .utility) { [weak self] in
            let blocked = FolderAccess.unreadable()
            await self?.finishAccessCheck(blocked)
        }
    }

    private func finishAccessCheck(_ blocked: [String]) {
        blockedFolders = blocked
        isCheckingAccess = false
    }
}

/// The folders macOS protects with a per-app prompt.
enum FolderAccess {
    static let protected = ["Desktop", "Documents", "Downloads"]

    /// Opening a protected folder asks macOS for access the first time (the prompt
    /// blocks this thread until it's answered), then just succeeds or fails.
    static func unreadable() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return protected.filter { name in
            guard let directory = opendir(home + "/" + name) else { return true }
            closedir(directory)
            return false
        }
    }
}

@MainActor
final class SpotlightSearch {
    /// Spotlight results looked at per update; a short query can match many thousands.
    static let scanLimit = 2000

    private let query = NSMetadataQuery()
    private let text: String
    private let limit: Int
    private let continuation: AsyncStream<[FileSearchHit]>.Continuation
    private let home: String
    private let standard: [FileSearchHit]
    private var observers: [NSObjectProtocol] = []
    private var isStopped = false

    init(text: String, limit: Int, continuation: AsyncStream<[FileSearchHit]>.Continuation) {
        self.text = text
        self.limit = limit
        self.continuation = continuation
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.home = home
        standard = Self.standardFolders(matching: Self.words(in: text), home: home)
    }

    func start() {
        let words = Self.words(in: text)
        guard !words.isEmpty else {
            continuation.yield([])
            continuation.finish()
            return
        }
        // The standard folders straight away, before Spotlight answers.
        continuation.yield(Array(standard.prefix(limit)))
        let terms = words.map { NSPredicate(format: "%K LIKE[cd] %@", "kMDItemFSName", "*\($0)*") }
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: terms)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.15
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSMetadataQueryGatheringProgress,
            object: query,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        })
        observers.append(center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publish()
                self?.continuation.finish()
                self?.stop()
            }
        })
        if !query.start() {
            continuation.finish()
            stop()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        query.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    private func publish() {
        guard !isStopped else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var hits = standard
        var seen = Set(standard.map(\.url.path))
        for index in 0..<min(query.resultCount, Self.scanLimit) {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: "kMDItemPath") as? String,
                  Self.isInteresting(path, home: home),
                  seen.insert(path).inserted
            else { continue }
            let url = URL(fileURLWithPath: path)
            let contentType = item.value(forAttribute: "kMDItemContentType") as? String
            let name = item.value(forAttribute: "kMDItemDisplayName") as? String ?? url.lastPathComponent
            hits.append(FileSearchHit(
                url: url,
                name: name,
                isDirectory: contentType == "public.folder",
                lastUsed: item.value(forAttribute: "kMDItemLastUsedDate") as? Date
            ))
        }
        continuation.yield(Array(Self.rank(hits, query: text).prefix(limit)))
    }

    // MARK: Ranking

    /// Exact names, then names starting with the query, then a word starting with it,
    /// then the rest. Within each: shallower paths, then recently used, then by name.
    static func rank(_ hits: [FileSearchHit], query: String) -> [FileSearchHit] {
        let needle = fold(words(in: query).joined(separator: " "))
        let keyed = hits.map { hit in
            (hit: hit, tier: tier(of: hit, needle: needle), depth: hit.url.pathComponents.count)
        }
        return keyed.sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            let left = lhs.hit.lastUsed ?? .distantPast
            let right = rhs.hit.lastUsed ?? .distantPast
            if left != right { return left > right }
            return lhs.hit.name.localizedStandardCompare(rhs.hit.name) == .orderedAscending
        }.map(\.hit)
    }

    private static func tier(of hit: FileSearchHit, needle: String) -> Int {
        let name = fold(hit.name)
        let stem = fold((hit.name as NSString).deletingPathExtension)
        if name == needle || stem == needle {
            return 0
        }
        if name.hasPrefix(needle) {
            return 1
        }
        let words = name.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        if words.contains(where: { $0.hasPrefix(needle) }) {
            return 2
        }
        return 3
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: Standard folders

    /// Folders everyone means by name ("downloads"), found without Spotlight, which
    /// doesn't always return them.
    static func standardFolders(matching words: [String], home: String) -> [FileSearchHit] {
        guard !words.isEmpty else { return [] }
        let names = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"]
        var folders = names.map { (name: $0, path: home + "/" + $0) }
        folders.append((name: "iCloud Drive", path: home + "/Library/Mobile Documents/com~apple~CloudDocs"))
        folders.insert((name: (home as NSString).lastPathComponent, path: home), at: 0)
        return folders.compactMap { folder in
            let name = fold(folder.name)
            guard words.allSatisfy({ name.contains(fold($0)) }) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return FileSearchHit(url: URL(fileURLWithPath: folder.path), name: folder.name, isDirectory: true)
        }
    }

    // MARK: Query text

    /// The typed words, without characters that would change the predicate's meaning.
    static func words(in text: String) -> [String] {
        sanitize(text).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Wildcards and quotes would change the predicate's meaning.
    static func sanitize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !"*?\\\"".contains($0) }
    }

    /// Skips hidden files, app bundles (the Apps provider has those) and ~/Library,
    /// except iCloud Drive.
    static func isInteresting(_ path: String, home: String) -> Bool {
        if path.hasSuffix(".app") || path.contains("/.") {
            return false
        }
        let library = home + "/Library/"
        if path.hasPrefix(library) {
            return path.hasPrefix(library + "Mobile Documents/")
        }
        return true
    }
}
