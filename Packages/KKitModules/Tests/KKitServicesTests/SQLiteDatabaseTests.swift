import Foundation
import KKitServices
import KKitServicesAPI
import Testing

struct SQLiteDatabaseTests {
    @Test func bindsAndReadsEveryType() throws {
        let db = try SQLiteDatabase(url: nil)
        try db.execute("CREATE TABLE t (i INTEGER, r REAL, s TEXT, b BLOB, n TEXT)")
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        try db.execute("INSERT INTO t VALUES (?, ?, ?, ?, ?)", [42, DatabaseValue(date), "héllo", DatabaseValue(Data([1, 2, 3])), .null])
        #expect(db.lastInsertRowID == 1)
        #expect(db.changes == 1)
        let row = try #require(try db.query("SELECT * FROM t").first)
        #expect(row["i"].int == 42)
        #expect(row["r"].date == date)
        #expect(row["s"].string == "héllo")
        #expect(row["b"].data == Data([1, 2, 3]))
        #expect(row["n"] == .null)
        #expect(row["missing"] == .null)
    }

    @Test func rollsBackFailedTransactions() throws {
        let db = try SQLiteDatabase(url: nil)
        try db.execute("CREATE TABLE t (v INTEGER)")
        #expect(throws: (any Error).self) {
            try db.transaction {
                try db.execute("INSERT INTO t VALUES (1)")
                try db.execute("NOT SQL")
            }
        }
        #expect(try db.query("SELECT COUNT(*) AS n FROM t").first?["n"].int == 0)
        try db.transaction { try db.execute("INSERT INTO t VALUES (2)") }
        #expect(try db.query("SELECT COUNT(*) AS n FROM t").first?["n"].int == 1)
    }

    @Test func runsEachMigrationOnce() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SQLiteTests-\(UUID().uuidString).sqlite")
        var runs = 0
        let migrations: [(any Database) throws -> Void] = [
            { db in
                runs += 1
                try db.execute("CREATE TABLE a (v TEXT)")
            },
            { db in
                runs += 1
                try db.execute("CREATE TABLE b (v TEXT)")
            },
        ]
        do {
            let db = try SQLiteDatabase(url: url)
            try db.migrate(migrations)
            #expect(db.userVersion == 2)
            db.close()
        }
        let reopened = try SQLiteDatabase(url: url)
        try reopened.migrate(migrations)
        #expect(runs == 2)
        try reopened.execute("INSERT INTO b VALUES ('kept')")
        #expect(try reopened.query("SELECT v FROM b").map { $0["v"].string } == ["kept"])
    }

    @Test func reportsErrors() throws {
        let db = try SQLiteDatabase(url: nil)
        #expect(throws: DatabaseError.self) {
            try db.query("SELECT * FROM nowhere")
        }
    }
}
