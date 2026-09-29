import Foundation
import AnchorCore


/// anchor — 결정 기록 + 회고 CLI.
///
/// 핵심 명령:
///   anchor new "제목"        결정 추가 (cwd 로 프로젝트 자동 감지)
///   anchor ls               목록
///   anchor show <id>        상세
///   anchor retro [N]        최근 N일 회고
///   anchor projects         프로젝트별 요약
@main
struct Anchor {
    static func main() {
        var argv = Array(CommandLine.arguments.dropFirst())
        // 전역 옵션: --db <path>
        var dbPath: String? = nil
        if let i = argv.firstIndex(of: "--db"), i + 1 < argv.count {
            dbPath = argv[i + 1]
            argv.removeSubrange(i...(i + 1))
        }
        guard let cmd = argv.first else {
            Out.print(Usage.text)
            exit(0)
        }
        if cmd == "-h" || cmd == "--help" || cmd == "help" {
            Out.print(Usage.text)
            exit(0)
        }

        do {
            let store = try dbPath.map { try Store(path: $0) } ?? (try Store.open())
            let args = Args(Array(argv.dropFirst()))
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let proj = ProjectRef.detect(cwd: cwd)
            let code = try run(cmd, args: args, argv: argv, store: store,
                               proj: proj, cwd: cwd)
            exit(code)
        } catch {
            Out.eprint("\(Out.red("에러:")) \(error)")
            exit(1)
        }
    }

    static func run(_ cmd: String, args: Args, argv: [String], store: Store,
                    proj: ProjectRef?, cwd: URL) throws -> Int32 {
        switch cmd {
        case "new", "n", "add":
            return try cmdNew(args, argv, store, proj)
        case "ls", "list":
            return try cmdList(args, store, proj)
        case "show", "view":
            return try cmdShow(args, store, proj)
        case "edit":
            return try cmdEdit(args, store, proj)
        case "set":
            return try cmdSet(args, store)
        case "rm", "remove":
            return try cmdRemove(args, store)
        case "alt":
            return try cmdAlt(args, argv, store)
        case "retro":
            return try cmdRetro(args, store, proj)
        case "stats":
            return try cmdStats(args, store)
        case "note":
            return try cmdNote(args, store, proj)
        case "projects", "p":
            return try cmdProjects(store)
        case "tags":
            return try cmdTags(store)
        case "export":
            return try cmdExport(args, store)
        default:
            Out.eprint("\(Out.red("알 수 없는 명령:")) \(cmd)")
            Out.print(Usage.text)
            return 1
        }
    }

    // MARK: - new

    static func cmdNew(_ a: Args, _ argv: [String], _ store: Store,
                       _ proj: ProjectRef?) throws -> Int32 {
        guard let title = a.positional.first, !title.isEmpty else {
            Out.eprint("사용법: anchor new \"제목\" [--context ...] [--choice ...] [--alt \"옵션::이유\"]")
            return 1
        }
        let now = Date()
        let d = Decision(
            id: 0,
            project: a.str("project") ?? proj?.name ?? "unknown",
            title: title,
            context: a.str("context", default: ""),
            choice: a.str("choice", default: ""),
            rejected: a.str("rejected", default: ""),
            status: a.str("status").flatMap(Decision.Status.parse) ?? .accepted,
            tags: parseTags(a.str("tags", default: "")),
            createdAt: now, updatedAt: now)

        // --alt 는 여러 번 지정할 수 있지만 Args 는 같은 키를 덮어쓴다.
        // 그래서 원본 argv 를 직접 훑어 모든 값을 모은다.
        let altSpecs = allAltSpecs(argv)
        let id = try store.addDecision(d)
        let alts = altSpecs.enumerated().map { i, raw -> Alternative in
            let parts = raw.components(separatedBy: "::")
            return Alternative(id: 0, decisionID: id,
                               option: parts.first ?? raw,
                               whyNot: parts.count > 1 ? parts[1...].joined(separator: "::") : "",
                               rank: i + 1)
        }
        try store.addAlternatives(alts, decisionID: id)

        Out.print("\(Out.green("✓")) #\(id)  \(d.title)  \(Out.cyan(d.project))")
        return 0
    }

    /// --alt 는 반복 지정이 가능하므로 원본 argv 에서 전부 뽑아낸다.
    /// 전역 변수를 쓰면 Swift 6 Strict Concurrency 에서 컴파일 에러가 난다.
    static func allAltSpecs(_ argv: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < argv.count {
            if argv[i] == "--alt", i + 1 < argv.count {
                out.append(argv[i + 1]); i += 2
            } else if argv[i].hasPrefix("--alt=") {
                out.append(String(argv[i].dropFirst(6))); i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// 태그 문자열 파싱. CLI 와 테스트가 함께 쓴다.
    /// 콤마/공백 구분, 앞뒤 # 제거, 빈 항목 제거.
    static func parseTags(_ s: String) -> [String] {
        TagParser.parse(s)
    }

    // MARK: - ls

    static func cmdList(_ a: Args, _ store: Store, _ proj: ProjectRef?) throws -> Int32 {
        var f = Store.Filter()
        // --all 이 없으면 현재 프로젝트만. 프로젝트 감지가 안 되면 전체.
        if !a.bool("all") {
            f.project = a.str("project") ?? proj?.name
        } else if let p = a.str("project") {
            f.project = p
        }
        f.status = a.str("status").flatMap(Decision.Status.parse)
        f.tag = a.str("tag")
        f.search = a.str("search")
        f.limit = a.int("limit", default: 30)

        let rows = try store.list(f)
        if rows.isEmpty {
            Out.print(Out.dim("결정 기록이 없습니다. anchor new \"제목\" 으로 시작하세요."))
            return 0
        }
        for d in rows { Out.print(Render.line(d, showProject: a.bool("all") || f.project == nil)) }
        Out.print("")
        Out.print(Out.dim("\(rows.count)건  ·  anchor show <id>  ·  anchor retro 7"))
        return 0
    }

    // MARK: - show

    static func cmdShow(_ a: Args, _ store: Store, _ proj: ProjectRef?) throws -> Int32 {
        guard let raw = a.positional.first, let id = Int64(raw) else {
            Out.eprint("사용법: anchor show <id>")
            return 1
        }
        guard let d = try store.decision(id: id) else {
            Out.eprint("\(Out.red("없음:")) #\(id)")
            return 1
        }
        Out.print(Render.detail(d, alts: try store.alternatives(decisionID: id),
                                cwdIsSame: d.project == proj?.name))
        return 0
    }

    // MARK: - edit / set

    static func cmdEdit(_ a: Args, _ store: Store, _ proj: ProjectRef?) throws -> Int32 {
        guard let raw = a.positional.first, let id = Int64(raw),
              var d = try store.decision(id: id) else {
            Out.eprint("사용법: anchor edit <id> \"새 제목\"")
            return 1
        }
        if a.positional.count > 1 { d.title = a.positional[1] }
        if let c = a.str("context") { d.context = c }
        if let c = a.str("choice") { d.choice = c }
        if let c = a.str("rejected") { d.rejected = c }
        if let t = a.str("tags") { d.tags = parseTags(t) }
        d.updatedAt = Date()
        try store.updateDecision(d)
        Out.print("\(Out.green("✓")) #\(id) 수정됨")
        return 0
    }

    static func cmdSet(_ a: Args, _ store: Store) throws -> Int32 {
        guard let raw = a.positional.first, let id = Int64(raw),
              var d = try store.decision(id: id) else {
            Out.eprint("사용법: anchor set <id> --status accepted|proposed|superseded|rejected")
            return 1
        }
        if let s = a.str("status") {
            guard let st = Decision.Status.parse(s) else {
                Out.eprint("\(Out.red("잘못된 상태:")) \(s)  (accepted/proposed/superseded/rejected)")
                return 1
            }
            d.status = st
        }
        d.updatedAt = Date()
        try store.updateDecision(d)
        Out.print("\(Out.green("✓")) #\(id) → \(d.status.badge)")
        return 0
    }

    // MARK: - rm

    static func cmdRemove(_ a: Args, _ store: Store) throws -> Int32 {
        guard let raw = a.positional.first, let id = Int64(raw) else {
            Out.eprint("사용법: anchor rm <id>")
            return 1
        }
        if !a.bool("yes") {
            guard let d = try store.decision(id: id) else {
                Out.eprint("\(Out.red("없음:")) #\(id)"); return 1
            }
            Out.print("삭제할 결정: \(Out.bold(d.title))")
            Out.print(Out.dim("확인하려면 --yes 를 붙이세요."))
            return 0
        }
        try store.deleteDecision(id)
        Out.print("\(Out.green("✓")) #\(id) 삭제됨")
        return 0
    }

    // MARK: - alt

    static func cmdAlt(_ a: Args, _ argv: [String], _ store: Store) throws -> Int32 {
        guard let raw = a.positional.first, let id = Int64(raw) else {
            Out.eprint("사용법: anchor alt <id> \"옵션::버린 이유\"")
            return 1
        }
        let specs = allAltSpecs(argv)
        guard !specs.isEmpty else {
            let alts = try store.alternatives(decisionID: id)
            if alts.isEmpty { Out.print(Out.dim("기록된 대안이 없습니다.")) }
            for x in alts { Out.print("  • \(x.option)\(x.whyNot.isEmpty ? "" : "  \(Out.dim("→ \(x.whyNot)"))")") }
            return 0
        }
        let alts = specs.enumerated().map { i, raw -> Alternative in
            let p = raw.components(separatedBy: "::")
            return Alternative(id: 0, decisionID: id, option: p.first ?? raw,
                               whyNot: p.count > 1 ? p[1...].joined(separator: "::") : "",
                               rank: i + 1)
        }
        try store.addAlternatives(alts, decisionID: id)
        Out.print("\(Out.green("✓")) #\(id) 대안 \(alts.count)개 추가")
        return 0
    }

    // MARK: - retro / note

    static func cmdRetro(_ a: Args, _ store: Store, _ proj: ProjectRef?) throws -> Int32 {
        let days = a.positional.first.flatMap(Int.init) ?? a.int("days", default: 7)
        let project = a.bool("all") ? nil : (a.str("project") ?? proj?.name)
        let since = TimeParser.daysAgoStart(days)
        let f = Store.Filter(project: project, status: nil, tag: nil,
                             since: since, search: nil, limit: 500, offset: 0)
        let decisions = try store.list(f)
        let retros = try store.retros(project: project, limit: 5)
        Out.print(Render.retro(days: days, project: project,
                              decisions: decisions, retros: retros))
        return 0
    }

    /// 집계 출력. GUI 대시보드가 보여주는 값을 터미널에서도 확인할 수 있게 한다.
    static func cmdStats(_ a: Args, _ store: Store) throws -> Int32 {
        let days = a.int("days", default: 28)
        let project = a.str("project")
        let s = try store.stats(days: days, project: project)
        Out.print(Render.stats(s))
        return 0
    }

    static func cmdNote(_ a: Args, _ store: Store, _ proj: ProjectRef?) throws -> Int32 {
        guard let title = a.positional.first, !title.isEmpty else {
            Out.eprint("사용법: anchor note \"회고 제목\" --summary \"요약\" [--mood good]")
            return 1
        }
        let r = Retro(id: 0,
                      project: a.str("project") ?? proj?.name ?? "unknown",
                      title: title,
                      summary: a.str("summary", default: ""),
                      mood: a.str("mood", default: ""),
                      createdAt: Date())
        let id = try store.addRetro(r)
        Out.print("\(Out.green("✓")) 회고 노트 #\(id) 저장됨")
        return 0
    }

    // MARK: - projects / tags / export

    static func cmdProjects(_ store: Store) throws -> Int32 {
        let s = try store.query("""
            SELECT project, COUNT(*), MAX(created_at) FROM decisions
            GROUP BY project ORDER BY MAX(created_at) DESC
            """)
        var rows: [(String, Int64, Date?)] = []
        while try s.next() {
            rows.append((s.colText(0) ?? "", s.colInt(1), s.colDate(2)))
        }
        guard !rows.isEmpty else { Out.print(Out.dim("아직 프로젝트가 없습니다.")); return 0 }
        let total = rows.reduce(0) { $0 + $1.1 }
        for (name, n, last) in rows {
            let bar = String(repeating: "█", count: max(1, Int(Double(n) / Double(total) * 20)))
            Out.print("  \(Out.cyan(name.padding(toLength: max(name.count, 24), withPad: " ", startingAt: 0)))  \(bar)  \(n)건  \(Out.dim(TimeParser.shortRelative(last ?? Date())))")
        }
        return 0
    }

    static func cmdTags(_ store: Store) throws -> Int32 {
        let tags = try store.allTags()
        guard !tags.isEmpty else { Out.print(Out.dim("태그가 없습니다.")); return 0 }
        for t in tags { Out.print("  \(Out.blue("#\(t)"))") }
        return 0
    }

    /// 마크다운 export — 포폴/문서에 붙여넣기용.
    static func cmdExport(_ a: Args, _ store: Store) throws -> Int32 {
        let project = a.str("project") ?? (a.bool("all") ? nil : nil)
        let days = a.int("days", default: 90)
        let f = Store.Filter(project: project, status: nil, tag: a.str("tag"),
                             since: TimeParser.daysAgoStart(days),
                             search: nil, limit: 1000, offset: 0)
        let rows = try store.list(f)
        if a.bool("json") {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            enc.dateEncodingStrategy = .iso8601
            struct Row: Codable {
                let id: Int64, project: String, title: String, context: String
                let choice: String, rejected: String, status: String
                let tags: [String], createdAt: Date
            }
            let payload = rows.map {
                Row(id: $0.id, project: $0.project, title: $0.title, context: $0.context,
                    choice: $0.choice, rejected: $0.rejected,
                    status: $0.status.rawValue, tags: $0.tags, createdAt: $0.createdAt)
            }
            Out.print(String(data: try enc.encode(payload), encoding: .utf8) ?? "[]")
            return 0
        }
        // 마크다운
        Out.print("# 결정 기록\n")
        var lastProj = ""
        for d in rows {
            if d.project != lastProj {
                Out.print("\n## \(d.project)\n")
                lastProj = d.project
            }
            Out.print("### \(d.title)")
            Out.print("_\(TimeParser.localString(d.createdAt)) · \(d.status.label)_")
            if !d.context.isEmpty { Out.print("\n**상황**\n\n\(d.context)") }
            if !d.choice.isEmpty { Out.print("\n**결정**\n\n\(d.choice)") }
            let alts = try store.alternatives(decisionID: d.id)
            if !alts.isEmpty {
                Out.print("\n**기각한 대안**\n")
                for x in alts { Out.print("- \(x.option)\(x.whyNot.isEmpty ? " — \(x.whyNot)" : "")") }
            }
            Out.print("")
        }
        return 0
    }
}

enum Usage {
    static let text = """

    \(Out.bold("anchor")) — 결정 기록 + 회고 CLI

    \(Out.bold("기록"))
      anchor new "제목"                 결정 추가 (현재 git 저장소를 자동 감지)
        --context "상황"               왜 이 결정을 내리게 됐는지
        --choice "내용"                무엇으로 정했는지
        --alt "옵션::버린이유"         기각한 대안 (여러 번 가능)
        --tags "a,b"                  태그
        --status accepted|proposed|superseded|rejected
        --project 이름                 프로젝트 직접 지정

    \(Out.bold("조회"))
      anchor ls [--all] [--status s] [--tag t] [--search 키워드] [--limit N]
      anchor show <id>
      anchor projects
      anchor tags

    \(Out.bold("수정/삭제"))
      anchor edit <id> "새 제목" [--context ...] [--choice ...] [--tags ...]
      anchor set <id> --status accepted
      anchor alt <id> "옵션::이유"
      anchor rm <id> --yes

    \(Out.bold("회고"))
      anchor retro [일수] [--all] [--project 이름]
      anchor note "회고 제목" --summary "요약" [--mood good|tired]

    \(Out.bold("내보내기"))
      anchor export [--project 이름] [--days 90] [--json]

    \(Out.bold("전역 옵션"))
      --db <경로>                      다른 DB 파일 사용 (테스트용)

    """
}
