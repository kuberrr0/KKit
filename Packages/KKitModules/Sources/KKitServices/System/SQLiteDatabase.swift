import Foundation
import KKitServicesAPI
import SQLite3

/// A SQLite connection behind `Database`. Calls are serialised with a lock, so one
/// connection can be shared by an actor and background tasks.
///
/// Uses the SQLite that ships with macOS (FTS5 included), so there's no package
/// dependency.
public final class SQLiteDatabase: Database, @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    /// Opens or creates the database at `url`. `nil` opens a private in-memory one.
    public init(url: URL?) throws {
        let path = url?.path ?? ":memory:"
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "status \(status)"
            if let db { sqlite3_close(db) }
            throw DatabaseError("Couldn't open the database: \(message)", code: status)
        }
        handle = db
        sqlite3_busy_timeout(db, 2000)
        if url != nil {
            try execute("PRAGMA journal_mode = WAL", [])
        }
        try execute("PRAGMA foreign_keys = ON", [])
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    public func execute(_ sql: String, _ arguments: [DatabaseValue]) throws {
        try lock.withLock {
            guard let handle else { throw DatabaseError("The database is closed") }
            if arguments.isEmpty {
                var error: UnsafeMutablePointer<CChar>?
                let status = sqlite3_exec(handle, sql, nil, nil, &error)
                if status != SQLITE_OK {
                    let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
                    sqlite3_free(error)
                    throw DatabaseError(message, code: status)
                }
                return
            }
            let statement = try prepare(sql, handle: handle)
            defer { sqlite3_finalize(statement) }
            try bind(arguments, to: statement, handle: handle)
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else {
                throw DatabaseError(String(cString: sqlite3_errmsg(handle)), code: status)
            }
        }
    }

    public func query(_ sql: String, _ arguments: [DatabaseValue]) throws -> [DatabaseRow] {
        try lock.withLock {
            guard let handle else { throw DatabaseError("The database is closed") }
            let statement = try prepare(sql, handle: handle)
            defer { sqlite3_finalize(statement) }
            try bind(arguments, to: statement, handle: handle)
            var rows: [DatabaseRow] = []
            let count = sqlite3_column_count(statement)
            var names: [String] = []
            for index in 0..<count {
                names.append(String(cString: sqlite3_column_name(statement, index)))
            }
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else {
                    throw DatabaseError(String(cString: sqlite3_errmsg(handle)), code: status)
                }
                var values: [String: DatabaseValue] = [:]
                for index in 0..<count {
                    values[names[Int(index)]] = Self.column(statement, index)
                }
                rows.append(DatabaseRow(values))
            }
            return rows
        }
    }

    public var lastInsertRowID: Int64 {
        lock.withLock { handle.map { sqlite3_last_insert_rowid($0) } ?? 0 }
    }

    public var changes: Int {
        lock.withLock { handle.map { Int(sqlite3_changes($0)) } ?? 0 }
    }

    public func transaction<T>(_ work: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE", [])
        do {
            let value = try work()
            try execute("COMMIT", [])
            return value
        } catch {
            try? execute("ROLLBACK", [])
            throw error
        }
    }

    public var userVersion: Int {
        get { (try? query("PRAGMA user_version", []).first?["user_version"].int) ?? 0 }
        set { try? execute("PRAGMA user_version = \(max(newValue, 0))", []) }
    }

    /// Closes the connection. Later calls throw.
    public func close() {
        lock.withLock {
            if let handle {
                sqlite3_close_v2(handle)
            }
            handle = nil
        }
    }

    // MARK: Private

    private func prepare(_ sql: String, handle: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw DatabaseError(String(cString: sqlite3_errmsg(handle)), code: status)
        }
        return statement
    }

    private func bind(_ arguments: [DatabaseValue], to statement: OpaquePointer, handle: OpaquePointer) throws {
        let expected = Int(sqlite3_bind_parameter_count(statement))
        guard expected == arguments.count else {
            throw DatabaseError("Expected \(expected) arguments, got \(arguments.count)")
        }
        for (offset, value) in arguments.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(statement, index)
            case .integer(let number):
                status = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                status = sqlite3_bind_double(statement, index, number)
            case .text(let text):
                status = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .blob(let data):
                status = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
                }
            }
            guard status == SQLITE_OK else {
                throw DatabaseError(String(cString: sqlite3_errmsg(handle)), code: status)
            }
        }
    }

    private static func column(_ statement: OpaquePointer, _ index: Int32) -> DatabaseValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: text))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    /// `SQLITE_TRANSIENT`: SQLite copies the bytes before the call returns.
    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
