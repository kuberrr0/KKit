import Foundation
import KKitCore

/// A result saved to Favourites or Recent. Only storable kinds (not `.custom`) are kept,
/// because the host knows how to run them again without their provider.
public struct StoredResult: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: ResultIcon
    public var kind: ResultKind

    public init(id: String, title: String, subtitle: String?, icon: ResultIcon, kind: ResultKind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.kind = kind
    }

    public init?(_ result: SearchResult) {
        guard result.kind.isStorable else { return nil }
        self.init(id: result.id, title: result.title, subtitle: result.subtitle, icon: result.icon, kind: result.kind)
    }

    /// Back to a result the host can run by kind.
    public func makeResult(score: Double = 1) -> SearchResult {
        SearchResult(id: id, title: title, subtitle: subtitle, icon: icon, score: score, kind: kind)
    }
}

/// How often and how recently each result was picked, overall and for what was typed,
/// so the usual pick for "sa" (Safari) rises to the top.
public struct FrecencyStore: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var count: Int
        public var lastUsed: Date
    }

    public var items: [String: Entry] = [:]
    /// Query (normalized, at most 16 characters) → result id → times picked.
    public var queries: [String: [String: Int]] = [:]

    public init() {}

    static func key(_ query: String) -> String {
        String(FuzzyMatch.normalize(query).prefix(16))
    }

    public mutating func record(id: String, query: String, at date: Date = Date()) {
        var entry = items[id] ?? Entry(count: 0, lastUsed: date)
        entry.count += 1
        entry.lastUsed = date
        items[id] = entry
        let key = Self.key(query)
        if !key.isEmpty {
            queries[key, default: [:]][id, default: 0] += 1
        }
        prune()
    }

    /// 0…~0.55 added to a result's score.
    public func boost(id: String, query: String, now: Date = Date()) -> Double {
        var boost = 0.0
        if let entry = items[id] {
            let age = now.timeIntervalSince(entry.lastUsed)
            let recency: Double = age < 86_400 ? 1 : age < 7 * 86_400 ? 0.7 : age < 30 * 86_400 ? 0.4 : 0.2
            boost += min(0.25, 0.05 * log2(1 + Double(entry.count))) * recency
        }
        let key = Self.key(query)
        guard !key.isEmpty else { return boost }
        if let exact = queries[key]?[id] {
            boost += min(0.3, 0.1 * Double(exact))
        } else {
            // Picked after typing more ("saf" → Safari) also helps "sa".
            let longer = queries.filter { $0.key.hasPrefix(key) }.compactMap { $0.value[id] }.reduce(0, +)
            boost += min(0.15, 0.05 * Double(longer))
        }
        return boost
    }

    public mutating func remove(id: String) {
        items[id] = nil
        for key in queries.keys {
            queries[key]?[id] = nil
            if queries[key]?.isEmpty == true {
                queries[key] = nil
            }
        }
    }

    /// Keeps the 400 most recently used results and 400 queries.
    mutating func prune() {
        if items.count > 400 {
            let keep = Set(items.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(400).map(\.key))
            items = items.filter { keep.contains($0.key) }
        }
        if queries.count > 400 {
            let keep = Set(queries.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(400).map(\.key))
            queries = queries.filter { keep.contains($0.key) }
        }
    }
}

/// Favourites, Recent and frecency, saved as `floatingBar/history.json`.
public struct FloatingBarHistory: Codable, Sendable, Equatable {
    public static let fileName = "history"
    public static let maxRecents = 8

    public var favourites: [StoredResult] = []
    public var recents: [StoredResult] = []
    public var frecency = FrecencyStore()

    public init() {}

    public func isFavourite(_ id: String) -> Bool {
        favourites.contains { $0.id == id }
    }

    public mutating func recordRun(_ result: SearchResult, query: String, at date: Date = Date()) {
        frecency.record(id: result.id, query: query, at: date)
        guard let stored = StoredResult(result) else { return }
        recents.removeAll { $0.id == stored.id }
        recents.insert(stored, at: 0)
        if recents.count > Self.maxRecents {
            recents.removeLast(recents.count - Self.maxRecents)
        }
    }

    /// Adds or removes. Returns whether it's a favourite now.
    @discardableResult
    public mutating func toggleFavourite(_ result: SearchResult) -> Bool {
        if let index = favourites.firstIndex(where: { $0.id == result.id }) {
            favourites.remove(at: index)
            return false
        }
        guard let stored = StoredResult(result) else { return false }
        favourites.append(stored)
        return true
    }

    public mutating func removeRecent(_ id: String) {
        recents.removeAll { $0.id == id }
    }

    public mutating func clearRecents() {
        recents = []
        frecency = FrecencyStore()
    }
}
