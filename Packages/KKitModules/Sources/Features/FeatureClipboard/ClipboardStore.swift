import Foundation
import ImageIO
import KKitServicesAPI

/// The history on disk: a SQLite table with a full-text index, plus image files in an
/// `images` folder next to it. All work happens off the main actor.
actor ClipboardStore {
    private let db: any Database
    let imagesDirectory: URL
    /// Whether the FTS5 index exists (it needs SQLite's trigram tokenizer).
    private(set) var hasFullTextIndex = false

    init(db: any Database, imagesDirectory: URL) throws {
        self.db = db
        self.imagesDirectory = imagesDirectory
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try db.migrate(Self.migrations)
        hasFullTextIndex = Self.setUpFullTextIndex(db)
    }

    static var migrations: [(any Database) throws -> Void] { [
        { db in
            try db.execute("""
            CREATE TABLE items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT NOT NULL DEFAULT '',
                rtf BLOB,
                files TEXT,
                image TEXT,
                image_width INTEGER,
                image_height INTEGER,
                color TEXT,
                source_bundle TEXT,
                source_name TEXT,
                created REAL NOT NULL,
                last_used REAL NOT NULL,
                use_count INTEGER NOT NULL DEFAULT 1,
                pinned INTEGER NOT NULL DEFAULT 0,
                hash TEXT NOT NULL UNIQUE
            );
            CREATE INDEX items_last_used ON items(pinned DESC, last_used DESC);
            """)
        },
    ] }

    /// Creates the trigram index (substring search) and its triggers if SQLite has
    /// them; otherwise search falls back to LIKE.
    private static func setUpFullTextIndex(_ db: any Database) -> Bool {
        if (try? db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'items_fts'").isEmpty) == false {
            return true
        }
        do {
            try db.transaction {
                try db.execute("""
                CREATE VIRTUAL TABLE items_fts USING fts5(text, content='items', content_rowid='id', tokenize='trigram');
                CREATE TRIGGER items_fts_insert AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
                END;
                CREATE TRIGGER items_fts_delete AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
                END;
                CREATE TRIGGER items_fts_update AFTER UPDATE OF text ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, text) VALUES ('delete', old.id, old.text);
                    INSERT INTO items_fts(rowid, text) VALUES (new.id, new.text);
                END;
                INSERT INTO items_fts(items_fts) VALUES ('rebuild');
                """)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Writing

    /// Saves a draft, or moves the same content to the top if it's already there.
    @discardableResult
    func insert(_ draft: ClipboardDraft) throws -> ClipboardItem? {
        let hash = draft.contentHash
        var imageFile: String?
        var width: Int?
        var height: Int?
        if draft.kind == .image, let data = draft.imageData {
            let name = "\(hash).\(ClipboardItem.fileExtension(forImageType: draft.imageType))"
            let url = imagesDirectory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try data.write(to: url, options: .atomic)
            }
            imageFile = name
            (width, height) = Self.pixelSize(of: data)
        }
        let files = draft.fileURLs.isEmpty ? nil : draft.fileURLs.map(\.path).joined(separator: "\n")
        try db.execute("""
        INSERT INTO items (kind, text, rtf, files, image, image_width, image_height, color,
                           source_bundle, source_name, created, last_used, hash)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(hash) DO UPDATE SET
            last_used = excluded.last_used,
            use_count = use_count + 1,
            source_bundle = excluded.source_bundle,
            source_name = excluded.source_name,
            rtf = COALESCE(excluded.rtf, rtf),
            kind = CASE WHEN excluded.rtf IS NOT NULL THEN excluded.kind ELSE kind END
        """, [
            .text(draft.kind.rawValue),
            .text(draft.text),
            DatabaseValue(draft.rtf),
            DatabaseValue(files),
            DatabaseValue(imageFile),
            width.map { DatabaseValue($0) } ?? .null,
            height.map { DatabaseValue($0) } ?? .null,
            DatabaseValue(draft.color?.hex),
            DatabaseValue(draft.sourceBundleID),
            DatabaseValue(draft.sourceAppName),
            DatabaseValue(draft.date),
            DatabaseValue(draft.date),
            .text(hash),
        ])
        return try db.query("SELECT * FROM items WHERE hash = ?", [.text(hash)]).first.map(Self.item)
    }

    func markUsed(_ id: Int64, at date: Date = Date()) throws {
        try db.execute("UPDATE items SET last_used = ?, use_count = use_count + 1 WHERE id = ?", [DatabaseValue(date), .integer(id)])
    }

    func setPinned(_ id: Int64, _ pinned: Bool) throws {
        try db.execute("UPDATE items SET pinned = ? WHERE id = ?", [DatabaseValue(pinned), .integer(id)])
    }

    func delete(_ id: Int64) throws {
        let images = try db.query("SELECT image FROM items WHERE id = ?", [.integer(id)]).compactMap { $0["image"].string }
        try db.execute("DELETE FROM items WHERE id = ?", [.integer(id)])
        removeImages(images)
    }

    /// Removes everything, or everything but pinned items.
    func clear(keepPinned: Bool) throws {
        let condition = keepPinned ? "WHERE pinned = 0" : ""
        let images = try db.query("SELECT image FROM items \(condition)").compactMap { $0["image"].string }
        try db.execute("DELETE FROM items \(condition)")
        removeImages(images)
    }

    /// Drops unpinned items beyond `maxItems` or older than `maxAge`. Returns how many.
    @discardableResult
    func trim(maxItems: Int, maxAge: TimeInterval?, now: Date = Date()) throws -> Int {
        var removed = 0
        if let maxAge, maxAge > 0 {
            let cutoff = now.addingTimeInterval(-maxAge)
            let old = try db.query("SELECT id, image FROM items WHERE pinned = 0 AND last_used < ?", [DatabaseValue(cutoff)])
            if !old.isEmpty {
                try db.execute("DELETE FROM items WHERE pinned = 0 AND last_used < ?", [DatabaseValue(cutoff)])
                removeImages(old.compactMap { $0["image"].string })
                removed += old.count
            }
        }
        let limit = max(maxItems, 1)
        let extra = try db.query("""
        SELECT id, image FROM items WHERE pinned = 0
        ORDER BY last_used DESC LIMIT -1 OFFSET ?
        """, [DatabaseValue(limit)])
        if !extra.isEmpty {
            let ids = extra.compactMap { $0["id"].int }.map(String.init).joined(separator: ",")
            try db.execute("DELETE FROM items WHERE id IN (\(ids))")
            removeImages(extra.compactMap { $0["image"].string })
            removed += extra.count
        }
        return removed
    }

    private func removeImages(_ names: [String]) {
        for name in names where !name.contains("/") {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: Reading

    func count() throws -> Int {
        try db.query("SELECT COUNT(*) AS n FROM items").first?["n"].int ?? 0
    }

    func item(_ id: Int64) throws -> ClipboardItem? {
        try db.query("SELECT * FROM items WHERE id = ?", [.integer(id)]).first.map(Self.item)
    }

    /// Pinned first, then most recently used.
    func recent(limit: Int, kinds: Set<ClipboardKind>? = nil, pinnedOnly: Bool = false) throws -> [ClipboardItem] {
        var conditions: [String] = []
        var arguments: [DatabaseValue] = []
        Self.addKindFilter(kinds, to: &conditions, arguments: &arguments)
        if pinnedOnly {
            conditions.append("pinned = 1")
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        arguments.append(DatabaseValue(limit))
        return try db.query(
            "SELECT * FROM items \(whereClause) ORDER BY pinned DESC, last_used DESC LIMIT ?",
            arguments
        ).map(Self.item)
    }

    /// Items whose text contains every word of `query` (case-insensitive).
    func search(_ query: String, limit: Int, kinds: Set<ClipboardKind>? = nil, pinnedOnly: Bool = false) throws -> [ClipboardItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return try recent(limit: limit, kinds: kinds, pinnedOnly: pinnedOnly) }
        var conditions: [String] = []
        var arguments: [DatabaseValue] = []
        var join = ""
        let ftsWords = hasFullTextIndex ? words.filter { $0.count >= 3 } : []
        if !ftsWords.isEmpty {
            join = "JOIN items_fts ON items_fts.rowid = items.id"
            conditions.append("items_fts MATCH ?")
            arguments.append(.text(Self.matchExpression(ftsWords)))
        }
        for word in words where !ftsWords.contains(word) {
            conditions.append("items.text LIKE ? ESCAPE '\\'")
            arguments.append(.text("%" + Self.escapeLike(word) + "%"))
        }
        Self.addKindFilter(kinds, to: &conditions, arguments: &arguments, column: "items.kind")
        if pinnedOnly {
            conditions.append("items.pinned = 1")
        }
        arguments.append(DatabaseValue(limit))
        return try db.query("""
        SELECT items.* FROM items \(join)
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY items.pinned DESC, items.last_used DESC LIMIT ?
        """, arguments).map(Self.item)
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    func imageData(for item: ClipboardItem) -> Data? {
        imageURL(for: item).flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: Helpers

    /// `"word" AND "other"`, each quoted so FTS syntax in the text is literal.
    static func matchExpression(_ words: [String]) -> String {
        words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
    }

    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func addKindFilter(
        _ kinds: Set<ClipboardKind>?,
        to conditions: inout [String],
        arguments: inout [DatabaseValue],
        column: String = "kind"
    ) {
        guard let kinds, !kinds.isEmpty else { return }
        let sorted = kinds.map(\.rawValue).sorted()
        conditions.append("\(column) IN (\(Array(repeating: "?", count: sorted.count).joined(separator: ",")))")
        arguments.append(contentsOf: sorted.map { .text($0) })
    }

    static func item(_ row: DatabaseRow) -> ClipboardItem {
        ClipboardItem(
            id: Int64(row["id"].int ?? 0),
            kind: ClipboardKind(rawValue: row["kind"].string ?? "") ?? .text,
            text: row["text"].string ?? "",
            rtf: row["rtf"].data,
            fileURLs: (row["files"].string ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) },
            imageFile: row["image"].string,
            imageWidth: row["image_width"].int,
            imageHeight: row["image_height"].int,
            color: row["color"].string.flatMap { RGBAColor(hex: $0) },
            sourceBundleID: row["source_bundle"].string,
            sourceAppName: row["source_name"].string,
            createdAt: row["created"].date ?? Date(),
            lastUsedAt: row["last_used"].date ?? Date(),
            useCount: row["use_count"].int ?? 1,
            isPinned: row["pinned"].bool
        )
    }

    static func pixelSize(of data: Data) -> (Int?, Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return (nil, nil) }
        return (properties[kCGImagePropertyPixelWidth] as? Int, properties[kCGImagePropertyPixelHeight] as? Int)
    }
}
