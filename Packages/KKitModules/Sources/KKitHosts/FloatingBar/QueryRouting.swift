import Foundation
import KKitCore

/// Where a Floating Bar query goes.
public enum QueryRoute: Sendable, Hashable {
    /// Nothing typed: Favourites and Recent.
    case empty
    /// Every provider that takes part in root search.
    case root(String)
    /// One provider, chosen by its prefix (`f report`).
    case scoped(providerKey: String, text: String)
    /// A feature's mode, chosen by its prefix (`n buy milk`).
    case mode(modeKey: String, text: String)
}

/// Something a query can start with.
public struct PrefixTarget: Sendable, Hashable {
    public var key: String
    public var prefix: String

    public init(key: String, prefix: String) {
        self.key = key
        self.prefix = prefix
    }
}

/// Picks the route from the typed text. Modes win over providers, longer prefixes over
/// shorter ones, and letters in a prefix ignore case.
public enum QueryRouter {
    public static func route(_ raw: String, providers: [PrefixTarget], modes: [PrefixTarget]) -> QueryRoute {
        let text = String(raw.drop { $0.isWhitespace })
        guard !text.isEmpty else { return .empty }
        if let mode = match(text, modes) {
            return .mode(modeKey: mode.target.key, text: mode.rest)
        }
        if let provider = match(text, providers) {
            return .scoped(providerKey: provider.target.key, text: provider.rest)
        }
        return .root(text)
    }

    private static func match(_ text: String, _ targets: [PrefixTarget]) -> (target: PrefixTarget, rest: String)? {
        let lowered = text.lowercased()
        let sorted = targets.filter { !$0.prefix.isEmpty }.sorted { $0.prefix.count > $1.prefix.count }
        for target in sorted where lowered.hasPrefix(target.prefix.lowercased()) {
            let rest = String(text.dropFirst(target.prefix.count).drop { $0 == " " })
            return (target, rest)
        }
        return nil
    }
}

/// One provider's latest results, for ranking.
public struct ProviderBatch: Sendable {
    public var key: String
    /// Provider order (commands first, then features in catalog order): breaks ties.
    public var order: Int
    /// Root search weight: files count less than apps and commands.
    public var weight: Double
    public var results: [SearchResult]

    public init(key: String, order: Int, weight: Double = 1, results: [SearchResult]) {
        self.key = key
        self.order = order
        self.weight = weight
        self.results = results
    }
}

/// Merges providers' results: provider score × weight + frecency, duplicates (same id)
/// keep their best score, fallbacks go last.
public enum ResultRanker {
    public static func rank(
        _ batches: [ProviderBatch],
        query: String,
        frecency: FrecencyStore,
        now: Date = Date(),
        limit: Int = 40,
        fallbackLimit: Int = 3
    ) -> [SearchResult] {
        struct Candidate {
            var score: Double
            var order: Int
            var index: Int
            var result: SearchResult
        }
        var best: [String: Candidate] = [:]
        var fallbacks: [Candidate] = []
        for batch in batches {
            for (index, result) in batch.results.enumerated() {
                if result.isFallback {
                    fallbacks.append(Candidate(score: 0, order: batch.order, index: index, result: result))
                    continue
                }
                let score = result.score * batch.weight + frecency.boost(id: result.id, query: query, now: now)
                if let existing = best[result.id], existing.score >= score {
                    continue
                }
                best[result.id] = Candidate(score: score, order: batch.order, index: index, result: result)
            }
        }
        let ranked = best.values.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.index < rhs.index
        }
        var output: [SearchResult] = ranked.prefix(limit).map { candidate in
            var result = candidate.result
            result.score = candidate.score
            return result
        }
        var seen = Set(output.map(\.id))
        let orderedFallbacks = fallbacks.sorted { ($0.order, $0.index) < ($1.order, $1.index) }
        var added = 0
        for fallback in orderedFallbacks where added < fallbackLimit && !seen.contains(fallback.result.id) {
            output.append(fallback.result)
            seen.insert(fallback.result.id)
            added += 1
        }
        return output
    }
}
