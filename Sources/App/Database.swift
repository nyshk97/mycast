import Foundation
import SQLite3

/// system の libsqlite3 の薄いラッパ。メインスレッドからだけ使う。
///
/// スキーマは `PRAGMA user_version` でバージョン管理する。テーブルを足すときは `migrations` の
/// 末尾に 1 要素足すだけにし、既存の要素は書き換えない（既存の DB はその続きからしか流れない）。
final class Database {
    enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null
    }

    struct DBError: Error, CustomStringConvertible {
        let description: String
    }

    static let migrations: [String] = [
        // v1: 使用履歴（アプリ・設定パネル・コマンド・絵文字）とアプリ一覧のキャッシュ
        """
        CREATE TABLE usage (key TEXT PRIMARY KEY, count INTEGER NOT NULL, last_used REAL NOT NULL);
        CREATE TABLE app_cache (path TEXT PRIMARY KEY, name TEXT NOT NULL, english TEXT NOT NULL);
        """,
        // v2: クリップボード履歴
        """
        CREATE TABLE clipboard (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          text TEXT,
          image_file TEXT,
          width INTEGER,
          height INTEGER,
          dedupe_hash TEXT NOT NULL UNIQUE,
          source_app TEXT,
          created_at REAL NOT NULL,
          last_copied_at REAL NOT NULL
        );
        CREATE INDEX clipboard_last_copied ON clipboard(last_copied_at DESC);
        """,
    ]

    private var db: OpaquePointer?
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw DBError(description: "open failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        try exec("PRAGMA journal_mode=WAL;")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    var userVersion: Int {
        (try? query("PRAGMA user_version;") { Int($0.int(0)) }.first) ?? 0
    }

    private func migrate() throws {
        let current = userVersion
        guard current < Self.migrations.count else { return }
        for v in current..<Self.migrations.count {
            try exec("BEGIN;")
            do {
                try exec(Self.migrations[v])
                try exec("PRAGMA user_version = \(v + 1);")
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
            Log.write("db.migrated to v\(v + 1)")
        }
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError(description: "exec failed: \(msg) — \(sql.prefix(80))")
        }
    }

    @discardableResult
    func run(_ sql: String, _ binds: [Value] = []) throws -> Int {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DBError(description: "step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        return Int(sqlite3_changes(db))
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }

    func query<T>(_ sql: String, _ binds: [Value] = [], _ map: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(map(Row(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DBError(description: "step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        return out
    }

    private func prepare(_ sql: String, _ binds: [Value]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError(description: "prepare failed: \(String(cString: sqlite3_errmsg(db))) — \(sql.prefix(80))")
        }
        for (i, v) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .double(let d): sqlite3_bind_double(stmt, idx, d)
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    struct Row {
        let stmt: OpaquePointer?
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func text(_ i: Int32) -> String? {
            guard let p = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: p)
        }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    }
}

/// 使用履歴（frecency の元データ）。キーは `app:<path>` `pane:<id>` `cmd:<id>` `emoji:<文字>`
final class UsageStore {
    private let db: Database
    private(set) var all: [String: Usage] = [:]

    init(db: Database) {
        self.db = db
        let rows = (try? db.query("SELECT key, count, last_used FROM usage;") { row in
            (row.text(0) ?? "", Usage(count: Int(row.int(1)), lastUsed: Date(timeIntervalSince1970: row.double(2))))
        }) ?? []
        for (k, u) in rows { all[k] = u }
    }

    func usage(_ key: String) -> Usage? { all[key] }

    func record(_ key: String, now: Date = Date()) {
        var u = all[key] ?? Usage(count: 0, lastUsed: now)
        u.count += 1
        u.lastUsed = now
        all[key] = u
        do {
            try db.run(
                "INSERT INTO usage(key, count, last_used) VALUES(?, ?, ?) ON CONFLICT(key) DO UPDATE SET count = excluded.count, last_used = excluded.last_used;",
                [.text(key), .int(Int64(u.count)), .double(now.timeIntervalSince1970)])
        } catch {
            Log.write("usage.record_failed \(error)")
        }
    }
}
