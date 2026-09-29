import Foundation

/// 결정(decision) 하나.
public struct Decision: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var project: String
    public var title: String
    public var context: String
    public var choice: String
    public var rejected: String
    public var status: Status
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: Int64, project: String, title: String, context: String,
                choice: String, rejected: String, status: Status,
                tags: [String], createdAt: Date, updatedAt: Date) {
        self.id = id; self.project = project; self.title = title
        self.context = context; self.choice = choice; self.rejected = rejected
        self.status = status; self.tags = tags
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public enum Status: String, CaseIterable, Sendable {
        case proposed, accepted, superseded, rejected

        public var label: String {
            switch self {
            case .proposed:   return "제안"
            case .accepted:   return "채택"
            case .superseded: return "대체됨"
            case .rejected:   return "기각"
            }
        }
        /// 목록에서 쓰는 짧은 배지.
        public var badge: String {
            switch self {
            case .proposed:   return "제안"
            case .accepted:   return "채택"
            case .superseded: return "대체"
            case .rejected:   return "기각"
            }
        }
        public static func parse(_ s: String) -> Status? {
            // 한국어/영어 별칭 허용
            let norm = s.trimmingCharacters(in: .whitespaces).lowercased()
            if let s = Status(rawValue: norm) { return s }
            switch norm {
            case "p", "proposed", "제안": return .proposed
            case "a", "accepted", "채택", "확정": return .accepted
            case "s", "superseded", "대체됨", "대체": return .superseded
            case "r", "rejected", "기각", "버림": return .rejected
            default: return nil
            }
        }
    }
}

/// 대안 비교 항목. 선택 안 한 쪽을 버리지 않고 남기는 게 이 도구의 존재 이유다.
public struct Alternative: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var decisionID: Int64
    public var option: String
    public var whyNot: String
    public var rank: Int

    public init(id: Int64, decisionID: Int64, option: String, whyNot: String, rank: Int) {
        self.id = id; self.decisionID = decisionID
        self.option = option; self.whyNot = whyNot; self.rank = rank
    }
}

/// 회고(회고 세션) — 기간 단위로 묶은 결정들.
public struct Retro: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var project: String
    public var title: String
    public var summary: String
    public var mood: String
    public var createdAt: Date

    public init(id: Int64, project: String, title: String, summary: String,
                mood: String, createdAt: Date) {
        self.id = id; self.project = project; self.title = title
        self.summary = summary; self.mood = mood; self.createdAt = createdAt
    }
}

/// 저장소 위치. cwd 를 보고 어떤 프로젝트인지 자동으로 찾는다.
public struct ProjectRef: Equatable, Sendable {
    public var name: String
    public var root: URL
    public var remote: String
    public var branch: String

    public init(name: String, root: URL, remote: String, branch: String) {
        self.name = name; self.root = root
        self.remote = remote; self.branch = branch
    }

    /// git 저장소가 아니면 이름만 있는 fallback 을 만든다.
    public static func detect(cwd: URL) -> ProjectRef? {
        let fm = FileManager.default
        var dir = cwd.standardizedFileURL
        // 상위 디렉터리까지 .git 을 찾되, 홈을 넘지 않는다.
        var isRoot = false
        while !isRoot {
            let git = dir.appendingPathComponent(".git")
            if fm.fileExists(atPath: git.path) {
                let name = dir.lastPathComponent
                let remote = (try? run(["git", "-C", dir.path, "remote", "get-url", "origin"]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let branch = (try? run(["git", "-C", dir.path, "branch", "--show-current"]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // 원격이 있으면 저장소 이름(경로 끝) 을 프로젝트명으로 쓴다.
                var pname = name
                if !remote.isEmpty,
                   let last = URL(string: remote)?.lastPathComponent
                       .replacingOccurrences(of: ".git", with: "") {
                    pname = last
                }
                return ProjectRef(name: pname, root: dir, remote: remote, branch: branch)
            }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { isRoot = true }
            if dir.path == NSHomeDirectory() { isRoot = true }
            dir = parent
        }
        // git 저장소가 아니면 현재 폴더명을 그대로 프로젝트로 쓴다.
        let name = cwd.lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        return ProjectRef(name: name, root: cwd, remote: "", branch: "")
    }

    @discardableResult
    public static func run(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw NSError(domain: "git", code: 1) }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
