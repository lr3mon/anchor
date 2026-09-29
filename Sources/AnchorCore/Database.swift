import Foundation
import SQLite3

/// system libsqlite3 래퍼. 외부 의존성 없이 SQLite 를 쓴다.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DBError: Error, CustomStringConvertible {
    case open(String)
    case prepare(sql: String, message: String)
    case step(String)
    case migrate(String)

    public var description: String {
        switch self {
        case .open(let m):
            return "DB 열기 실패: \(m)"
        case .prepare(let sql, let m):
            return "SQL 준비 실패: \(m)\n  sql: \(sql)"
        case .step(let m):
            return "SQL 실행 실패: \(m)"
        case .migrate(let m):
            return "마이그레이션 실패: \(m)"
        }
    }
}

public final class DlDB {
    private var handle: OpaquePointer?
    let path: String

    public init(path: String) throws {
        self.path = path
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            let m = h.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(h)
            throw DBError.open(m)
        }
        handle = h
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try exec("PRAGMA busy_timeout=4000;")
    }

    deinit { sqlite3_close_v2(handle) }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }

    public func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
            let m = err.map { String(cString: $0) } ?? lastError
            sqlite3_free(err)
            throw DBError.step(m)
        }
    }

    public func prepare(_ sql: String) throws -> Stmt {
        var h: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &h, nil) == SQLITE_OK, let h else {
            throw DBError.prepare(sql: sql, message: lastError)
        }
        return Stmt(h)
    }

    /// Store 에서 쓰는 얇은 별칭.
    func prepareNamed(_ sql: String) throws -> Stmt { try prepare(sql) }

    /// 단일 정수 결과 (COUNT 등) — 내부에서 커서를 끝까지 돌린다.
    public func scalarInt(_ sql: String) throws -> Int64 {
        let s = try prepare(sql)
        guard try s.next() else { return 0 }
        return s.colInt(0)
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let r = try body()
            try exec("COMMIT;")
            return r
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    /// 한 행씩 순회하는 커서.
    public final class Stmt {
        private var h: OpaquePointer?
        private(set) var columnCount: Int32 = 0

        public init(_ h: OpaquePointer) {
            self.h = h
            self.columnCount = sqlite3_column_count(h)
        }
        deinit { sqlite3_finalize(h) }

        /// 다음 행으로 진행. true 면 읽을 행이 있음, false 면 끝.
        @discardableResult
        public func next() throws -> Bool {
            let rc = sqlite3_step(h)
            if rc == SQLITE_ROW { return true }
            if rc == SQLITE_DONE { return false }
            throw DBError.step(String(cString: sqlite3_errmsg(h)))
        }

        public func reset() { sqlite3_reset(h); sqlite3_clear_bindings(h) }

        public func bind(_ idx: Int32, _ v: String?) {
            if let v {
                sqlite3_bind_text(h, idx, v, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(h, idx)
            }
        }
        public func bind(_ idx: Int32, _ v: Int64) { sqlite3_bind_int64(h, idx, v) }
        public func bind(_ idx: Int32, _ v: Double) { sqlite3_bind_double(h, idx, v) }

        public func colInt(_ idx: Int32) -> Int64 { sqlite3_column_int64(h, idx) }
        public func colDouble(_ idx: Int32) -> Double { sqlite3_column_double(h, idx) }
        public func colText(_ idx: Int32) -> String? {
            guard let c = sqlite3_column_text(h, idx) else { return nil }
            return String(cString: c)
        }
        public func colDate(_ idx: Int32) -> Date? {
            guard let t = colText(idx) else { return nil }
            return TimeParser.date(fromISO: t)
        }
    }
}
