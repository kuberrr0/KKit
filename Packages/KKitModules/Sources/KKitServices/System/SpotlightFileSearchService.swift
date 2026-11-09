import Foundation
import KKitServicesAPI

/// File name search with `NSMetadataQuery`. Each search is its own query, started on
/// the main run loop and stopped when its stream ends.
@MainActor
public final class SpotlightFileSearchService: FileSearchService {
    public init() {}

    public func search(_ text: String, limit: Int) -> AsyncStream<[FileSearchHit]> {
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
}

@MainActor
final class SpotlightSearch {
    private let query = NSMetadataQuery()
    private let text: String
    private let limit: Int
    private let continuation: AsyncStream<[FileSearchHit]>.Continuation
    private var observers: [NSObjectProtocol] = []
    private var isStopped = false

    init(text: String, limit: Int, continuation: AsyncStream<[FileSearchHit]>.Continuation) {
        self.text = text
        self.limit = limit
        self.continuation = continuation
    }

    func start() {
        let term = Self.sanitize(text)
        guard !term.isEmpty else {
            continuation.yield([])
            continuation.finish()
            return
        }
        query.predicate = NSPredicate(format: "%K LIKE[cd] %@", "kMDItemFSName", "*\(term)*")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
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
            continuation.yield([])
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
        var hits: [FileSearchHit] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var index = 0
        while index < query.resultCount, hits.count < limit {
            defer { index += 1 }
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: "kMDItemPath") as? String,
                  Self.isInteresting(path, home: home)
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
        continuation.yield(hits)
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
