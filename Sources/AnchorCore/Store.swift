import Foundation

/// 스키마 관리 + 저장소 CRUD.
/// 마이그레이션은 user_version 을 올리며 순차 적용한다(롤백 시 되돌릴 필요 없는 단방향).
public final class Store {
    private var db: DlDB!
    public private(set) var path: String!

    /// 테스트는 임시 경로, CLI 는 기본 경로로 연다.
    public init(path: String) throws {
        self.path = path
        if path != ":memory:" {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        }
        self.db = try DlDB(path: path)
        try migrate()
    }

    public static func open() throws -> Store { try Store(path: Store.defaultPath()) }

    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".anchor/decisions.db").path
    }

    private func migrate() throws {
        let v = try db.scalarInt("PRAGMA user_version;")
        let migrations: [(Int, String)] = [
            (1, """
            CREATE TABLE decisions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                project     TEXT    NOT NULL,
                title       TEXT    NOT NULL,
                context     TEXT    NOT NULL DEFAULT '',
                choice      TEXT    NOT NULL DEFAULT '',
                rejected    TEXT    NOT NULL DEFAULT '',
                status      TEXT    NOT NULL DEFAULT 'accepted',
                tags        TEXT    NOT NULL DEFAULT '',
                created_at  TEXT    NOT NULL,
                updated_at  TEXT    NOT NULL
            );
            CREATE INDEX idx_decisions_project ON decisions(project);
            CREATE INDEX idx_decisions_created ON decisions(created_at DESC);
            """),
            (2, """
            CREATE TABLE alternatives (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                decision_id INTEGER NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
                option      TEXT    NOT NULL,
                why_not     TEXT    NOT NULL DEFAULT '',
                rank        INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX idx_alt_decision ON alternatives(decision_id);
            """),
            (3, """
            CREATE TABLE retros (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                project     TEXT    NOT NULL,
                title       TEXT    NOT NULL,
                summary     TEXT    NOT NULL DEFAULT '',
                mood        TEXT    NOT NULL DEFAULT '',
                created_at  TEXT    NOT NULL
            );
            CREATE INDEX idx_retro_project ON retros(project);
            """),
        ]
        guard v == 0 else { return }
        do {
            for (ver, sql) in migrations {
                try db.exec(sql)
                try db.exec("PRAGMA user_version = \(ver);")
            }
        } catch {
            throw DBError.migrate(String(describing: error))
        }
    }

    // MARK: - Decision

    @discardableResult
    public func addDecision(_ d: Decision) throws -> Int64 {
        try db.transaction {
            let s = try db.prepare("""
                INSERT INTO decisions
                    (project, title, context, choice, rejected, status, tags, created_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)
                """)
            s.bind(1, d.project)
            s.bind(2, d.title)
            s.bind(3, d.context)
            s.bind(4, d.choice)
            s.bind(5, d.rejected)
            s.bind(6, d.status.rawValue)
            s.bind(7, d.tags.joined(separator: ","))
            s.bind(8, TimeParser.isoString(d.createdAt))
            s.bind(9, TimeParser.isoString(d.updatedAt))
            try s.next()
            return try db.scalarInt("SELECT last_insert_rowid();")
        }
    }

    public func updateDecision(_ d: Decision) throws {
        let s = try db.prepare("""
            UPDATE decisions SET project=?, title=?, context=?, choice=?, rejected=?,
                status=?, tags=?, updated_at=? WHERE id=?
            """)
        s.bind(1, d.project); s.bind(2, d.title); s.bind(3, d.context)
        s.bind(4, d.choice);  s.bind(5, d.rejected); s.bind(6, d.status.rawValue)
        s.bind(7, d.tags.joined(separator: ","))
        s.bind(8, TimeParser.nowString())
        s.bind(9, d.id)
        try s.next()
    }

    public func deleteDecision(_ id: Int64) throws {
        let s = try db.prepare("DELETE FROM decisions WHERE id=?")
        s.bind(1, id)
        try s.next()
    }

    public func decision(id: Int64) throws -> Decision? {
        let s = try db.prepare("SELECT * FROM decisions WHERE id=?")
        s.bind(1, id)
        guard try s.next() else { return nil }
        return decode(s)
    }

    public struct Filter: Sendable {
        public var project: String?
        public var status: Decision.Status?
        public var tag: String?
        public var since: Date?
        public var search: String?
        public var limit: Int = 50
        public var offset: Int = 0

        public init(project: String? = nil, status: Decision.Status? = nil,
                    tag: String? = nil, since: Date? = nil, search: String? = nil,
                    limit: Int = 50, offset: Int = 0) {
            self.project = project; self.status = status; self.tag = tag
            self.since = since; self.search = search
            self.limit = limit; self.offset = offset
        }
    }

    public func list(_ f: Filter) throws -> [Decision] {
        var clauses: [String] = []
        var binds: [(Int32, String)] = []

        if let p = f.project { clauses.append("project = ?"); binds.append((Int32(binds.count + 1), p)) }
        if let st = f.status { clauses.append("status = ?"); binds.append((Int32(binds.count + 1), st.rawValue)) }
        if let t = f.tag {
            // tags 는 콤마로 저장돼 있으니 앞뒤 콤마로 감싸 정확히 일치시킨다.
            clauses.append("(',' || tags || ',') LIKE ?")
            binds.append((Int32(binds.count + 1), "%,\(t),%"))
        }
        if let since = f.since {
            clauses.append("created_at >= ?")
            binds.append((Int32(binds.count + 1), TimeParser.isoString(since)))
        }
        if let q = f.search, !q.isEmpty {
            clauses.append("(title LIKE ? OR context LIKE ? OR choice LIKE ?)")
            let like = "%\(q)%"
            binds.append((Int32(binds.count + 1), like))
            binds.append((Int32(binds.count + 1), like))
            binds.append((Int32(binds.count + 1), like))
        }

        let clause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT * FROM decisions \(clause) ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?"
        let s = try db.prepare(sql)
        for b in binds { s.bind(b.0, b.1) }
        s.bind(Int32(binds.count + 1), Int64(f.limit))
        s.bind(Int32(binds.count + 2), Int64(f.offset))
        var out: [Decision] = []
        while try s.next() { out.append(decode(s)) }
        return out
    }

    private func decode(_ s: DlDB.Stmt) -> Decision {
        let tagsRaw = s.colText(7) ?? ""
        let tags = tagsRaw.isEmpty ? [] : tagsRaw.split(separator: ",").map(String.init)
        return Decision(
            id: s.colInt(0),
            project: s.colText(1) ?? "",
            title: s.colText(2) ?? "",
            context: s.colText(3) ?? "",
            choice: s.colText(4) ?? "",
            rejected: s.colText(5) ?? "",
            status: Decision.Status(rawValue: s.colText(6) ?? "") ?? .accepted,
            tags: tags,
            createdAt: s.colDate(7) ?? Date(),
            updatedAt: s.colDate(8) ?? Date())
    }

    // MARK: - Alternatives

    public func addAlternatives(_ alts: [Alternative], decisionID: Int64) throws {
        guard !alts.isEmpty else { return }
        try db.transaction {
            for (i, a) in alts.enumerated() {
                let s = try db.prepare("""
                    INSERT INTO alternatives (decision_id, option, why_not, rank)
                    VALUES (?,?,?,?)
                    """)
                s.bind(1, decisionID)
                s.bind(2, a.option)
                s.bind(3, a.whyNot)
                s.bind(4, Int64(a.rank == 0 ? i + 1 : a.rank))
                try s.next()
            }
        }
    }

    public func alternatives(decisionID: Int64) throws -> [Alternative] {
        let s = try db.prepare(
            "SELECT id, decision_id, option, why_not, rank FROM alternatives WHERE decision_id=? ORDER BY rank, id")
        s.bind(1, decisionID)
        var out: [Alternative] = []
        while try s.next() {
            out.append(Alternative(id: s.colInt(0), decisionID: s.colInt(1),
                                   option: s.colText(2) ?? "", whyNot: s.colText(3) ?? "",
                                   rank: Int(s.colInt(4))))
        }
        return out
    }

    // MARK: - Retro

    @discardableResult
    public func addRetro(_ r: Retro) throws -> Int64 {
        try db.transaction {
            let s = try db.prepare(
                "INSERT INTO retros (project, title, summary, mood, created_at) VALUES (?,?,?,?,?)")
            s.bind(1, r.project); s.bind(2, r.title)
            s.bind(3, r.summary); s.bind(4, r.mood)
            s.bind(5, TimeParser.isoString(r.createdAt))
            try s.next()
            return try db.scalarInt("SELECT last_insert_rowid();")
        }
    }

    public func retros(project: String?, limit: Int = 20) throws -> [Retro] {
        let sql = project == nil
            ? "SELECT * FROM retros ORDER BY created_at DESC LIMIT ?"
            : "SELECT * FROM retros WHERE project=? ORDER BY created_at DESC LIMIT ?"
        let s = try db.prepare(sql)
        var i: Int32 = 1
        if let p = project { s.bind(i, p); i += 1 }
        s.bind(i, Int64(limit))
        var out: [Retro] = []
        while try s.next() {
            out.append(Retro(id: s.colInt(0), project: s.colText(1) ?? "",
                             title: s.colText(2) ?? "", summary: s.colText(3) ?? "",
                             mood: s.colText(4) ?? "", createdAt: s.colDate(5) ?? Date()))
        }
        return out
    }

    // MARK: - Stats

    public func projects() throws -> [String] {
        let s = try db.prepare(
            "SELECT project, COUNT(*) c, MAX(created_at) m FROM decisions GROUP BY project ORDER BY m DESC")
        var out: [(String, Int64)] = []
        while try s.next() { out.append((s.colText(0) ?? "", s.colInt(1))) }
        return out.map(\.0)
    }

    public func allTags() throws -> [String] {
        let s = try db.prepare("SELECT tags FROM decisions WHERE tags != ''")
        var set = Set<String>()
        while try s.next() {
            for t in (s.colText(0) ?? "").split(separator: ",") { set.insert(String(t)) }
        }
        return set.sorted()
    }

    /// 읽기 전용 커서를 직접 다뤄야 하는 명령용(집계 등).
    public func query(_ sql: String) throws -> DlDB.Stmt { try db.prepare(sql) }

    /// 여러 쓰기를 하나의 단위로. 하나라도 실패하면 전부 되돌린다.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try db.transaction(body)
    }

    public func count(_ f: Filter) throws -> Int64 {
        let got = try list(Filter(project: f.project, status: f.status, tag: f.tag,
                                  since: f.since, search: f.search,
                                  limit: Int(Int32.max), offset: 0))
        return Int64(got.count)
    }
}