import Foundation

/// A value bound to, or read from, a SQL statement.
public enum DatabaseValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

extension DatabaseValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .real(value) }
}

public extension DatabaseValue {
    init(_ value: String?) { self = value.map { .text($0) } ?? .null }
    init(_ value: Int) { self = .integer(Int64(value)) }
    init(_ value: Int64) { self = .integer(value) }
    init(_ value: Double) { self = .real(value) }
    init(_ value: Bool) { self = .integer(value ? 1 : 0) }
    init(_ value: Data?) { self = value.map { .blob($0) } ?? .null }
    /// Dates are stored as seconds since 1970.
    init(_ value: Date) { self = .real(value.timeIntervalSince1970) }

    var string: String? {
        switch self {
        case .text(let text): text
        case .integer(let value): String(value)
        case .real(let value): String(value)
        default: nil
        }
    }

    var int: Int? {
        switch self {
        case .integer(let value): Int(value)
        case .real(let value): Int(value)
        case .text(let text): Int(text)
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .real(let value): value
        case .text(let text): Double(text)
        default: nil
        }
    }

    var bool: Bool { (int ?? 0) != 0 }

    var data: Data? {
        switch self {
        case .blob(let data): data
        case .text(let text): Data(text.utf8)
        default: nil
        }
    }

    var date: Date? { double.map { Date(timeIntervalSince1970: $0) } }
}

/// One result row, by column name.
public struct DatabaseRow: Sendable, Hashable {
    public var values: [String: DatabaseValue]

    public init(_ values: [String: DatabaseValue]) {
        self.values = values
    }

    public subscript(_ column: String) -> DatabaseValue {
        values[column] ?? .null
    }
}

public struct DatabaseError: LocalizedError, Sendable {
    public var message: String
    public var code: Int32

    public init(_ message: String, code: Int32 = 0) {
        self.message = message
        self.code = code
    }

    public var errorDescription: String? { message }
}

/// A SQLite database (`StorageService.openDatabase`). Thread-safe: calls are
/// serialised, so features can use it from an actor or background task. Keep it off
/// the main actor for anything but tiny queries.
///
/// ```swift
/// try db.execute("INSERT INTO items (text) VALUES (?)", ["hello"])
/// let rows = try db.query("SELECT * FROM items WHERE text LIKE ?", ["%he%"])
/// ```
public protocol Database: AnyObject, Sendable {
    /// Runs one or more statements. Bindings apply to a single statement.
    func execute(_ sql: String, _ arguments: [DatabaseValue]) throws
    func query(_ sql: String, _ arguments: [DatabaseValue]) throws -> [DatabaseRow]
    /// The rowid of the last INSERT on this connection.
    var lastInsertRowID: Int64 { get }
    /// Rows changed by the last INSERT, UPDATE or DELETE.
    var changes: Int { get }
    /// Runs `work` in a transaction, rolling back if it throws.
    func transaction<T>(_ work: () throws -> T) throws -> T
    /// The user_version pragma, for migrations.
    var userVersion: Int { get set }
}

public extension Database {
    func execute(_ sql: String) throws {
        try execute(sql, [])
    }

    func query(_ sql: String) throws -> [DatabaseRow] {
        try query(sql, [])
    }

    /// Runs each migration whose index is at or past `userVersion`, in a transaction,
    /// and bumps the version after each.
    func migrate(_ migrations: [(any Database) throws -> Void]) throws {
        var version = userVersion
        while version < migrations.count {
            let step = migrations[version]
            try transaction { try step(self) }
            version += 1
            userVersion = version
        }
    }
}
