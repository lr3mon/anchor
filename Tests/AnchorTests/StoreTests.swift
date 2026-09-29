import Testing
import Foundation
@testable import AnchorCore

@Suite("Store — 결정 기록")
struct StoreTests {

    /// 매 테스트마다 임시 파일 DB 를 만들어 서로 격리한다.
    private func tempStore() throws -> (Store, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anchor-test-\(UUID().uuidString)")
        let db = dir.appendingPathComponent("t.db")
        let s = try Store(path: db.path)
        return (s, dir)
    }

    @Test("결정을 넣고 읽는다")
    func addAndFetch() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date()
        let id = try s.addDecision(Decision(
            id: 0, project: "anchor", title: "SQLite 채택",
            context: "외부 의존성 없이 하고 싶음", choice: "system libsqlite3",
            rejected: "GRDB", status: .accepted,
            tags: ["swift", "sqlite"], createdAt: now, updatedAt: now))

        let got = try #require(try s.decision(id: id))
        #expect(got.title == "SQLite 채택")
        #expect(got.project == "anchor")
        #expect(got.status == .accepted)
        #expect(got.tags == ["swift", "sqlite"])
        #expect(got.choice == "system libsqlite3")
    }

    @Test("대안은 순서대로 저장된다")
    func alternatives() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = try s.addDecision(Decision(
            id: 0, project: "p", title: "t", context: "", choice: "A",
            rejected: "", status: .accepted, tags: [],
            createdAt: Date(), updatedAt: Date()))
        try s.addAlternatives([
            Alternative(id: 0, decisionID: id, option: "B", whyNot: "의존성 추가", rank: 0),
            Alternative(id: 0, decisionID: id, option: "C", whyNot: " immature", rank: 0),
        ], decisionID: id)

        let alts = try s.alternatives(decisionID: id)
        #expect(alts.count == 2)
        #expect(alts[0].option == "B")
        #expect(alts[1].option == "C")
        #expect(alts[0].whyNot == "의존성 추가")
    }

    @Test("결정을 지우면 대안도 함께 사라진다 (ON DELETE CASCADE)")
    func cascadeDelete() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = try s.addDecision(Decision(
            id: 0, project: "p", title: "t", context: "", choice: "", rejected: "",
            status: .accepted, tags: [], createdAt: Date(), updatedAt: Date()))
        try s.addAlternatives([
            Alternative(id: 0, decisionID: id, option: "X", whyNot: "이유", rank: 1)
        ], decisionID: id)
        #expect(try s.alternatives(decisionID: id).count == 1)

        try s.deleteDecision(id)
        #expect(try s.alternatives(decisionID: id).isEmpty)
    }

    @Test("태그가 정확히 일치할 때만 걸린다 (부분 문자열 오탐 없음)")
    func tagFilterExact() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        func mk(_ tags: [String]) throws {
            _ = try s.addDecision(Decision(
                id: 0, project: "p", title: "t\(tags)", context: "", choice: "",
                rejected: "", status: .accepted, tags: tags,
                createdAt: Date(), updatedAt: Date()))
        }
        try mk(["swift"])
        try mk(["swiftt"])

        let exact = try s.list(Store.Filter(project: "p", status: nil, tag: "swift",
                                            since: nil, search: nil, limit: 50))
        #expect(exact.count == 1, "tag 'swift' 는 'swiftt' 를 잡으면 안 됨")
        // mk() 는 태그 배열을 제목에 그대로 넣으므로 제목으로 구분한다.
        #expect(exact.first?.tags == ["swift"])
    }

    @Test("프로젝트 필터가 다른 프로젝트를 섞어 넣지 않는다")
    func projectFilter() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        for p in ["alpha", "beta", "alpha"] {
            _ = try s.addDecision(Decision(
                id: 0, project: p, title: "\(p)-제목", context: "", choice: "",
                rejected: "", status: .accepted, tags: [],
                createdAt: Date(), updatedAt: Date()))
        }
        let a = try s.list(Store.Filter(project: "alpha", status: nil, tag: nil,
                                        since: nil, search: nil, limit: 50))
        #expect(a.count == 2)
        #expect(a.allSatisfy { $0.project == "alpha" })
    }

    @Test("since 필터가 과거 기록만 걸러낸다")
    func sinceFilter() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = Date(timeIntervalSinceNow: -40 * 86_400)
        let new = Date()
        for (t, d) in [("오래됨", old), ("최근", new)] {
            _ = try s.addDecision(Decision(
                id: 0, project: "p", title: t, context: "", choice: "", rejected: "",
                status: .accepted, tags: [], createdAt: d, updatedAt: d))
        }
        let recent = try s.list(Store.Filter(project: "p", status: nil, tag: nil,
                                             since: TimeParser.daysAgoStart(7),
                                             search: nil, limit: 50))
        #expect(recent.count == 1)
        #expect(recent.first?.title == "최근")
    }

    @Test("상태 변경이 저장되고 다시 읽어도 유지된다")
    func statusUpdate() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = try s.addDecision(Decision(
            id: 0, project: "p", title: "t", context: "", choice: "", rejected: "",
            status: .proposed, tags: [], createdAt: Date(), updatedAt: Date()))
        var d = try #require(try s.decision(id: id))
        #expect(d.status == .proposed)
        d.status = .superseded
        try s.updateDecision(d)
        #expect(try s.decision(id: id)?.status == .superseded)
    }

    @Test("트랜잭션 실패 시 일부만 쓰이지 않는다")
    func transactionRollback() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let before = try s.list(Store.Filter(project: "p", status: nil, tag: nil,
                                             since: nil, search: nil, limit: 100)).count
        #expect(throws: (any Error).self) {
            try s.transaction {
                _ = try s.addDecision(Decision(
                    id: 0, project: "p", title: "반드시 롤백", context: "", choice: "",
                    rejected: "", status: .accepted, tags: [],
                    createdAt: Date(), updatedAt: Date()))
                throw DBError.step("의도적 실패")
            }
        }
        let after = try s.list(Store.Filter(project: "p", status: nil, tag: nil,
                                            since: nil, search: nil, limit: 100)).count
        #expect(before == after, "롤백 후에도 증가하면 안 됨")
    }

    @Test("회고 노트를 저장하고 프로젝트별로 읽는다")
    func retros() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        for (p, t) in [("a", "1주차"), ("a", "2주차"), ("b", "다른")] {
            _ = try s.addRetro(Retro(id: 0, project: p, title: t, summary: "s",
                                     mood: "good", createdAt: Date()))
        }
        #expect(try s.retros(project: "a").count == 2)
        #expect(try s.retros(project: "b").count == 1)
        #expect(try s.retros(project: nil).count == 3)
    }

    @Test("DB 를 두 번 열어도 스키마 중복 생성 없이된다")
    func reopenIdempotent() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anchor-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("t.db")

        let s1 = try Store(path: db.path)
        _ = try s1.addDecision(Decision(
            id: 0, project: "p", title: "유지됨", context: "", choice: "", rejected: "",
            status: .accepted, tags: [], createdAt: Date(), updatedAt: Date()))

        let s2 = try Store(path: db.path)   // 두 번째 오픈
        let rows = try s2.list(Store.Filter(project: "p", status: nil, tag: nil,
                                            since: nil, search: nil, limit: 50))
        #expect(rows.count == 1)
        #expect(rows.first?.title == "유지됨")
    }
}

@Suite("Model — 파싱 규칙")
struct ModelTests {

    @Test("상태 별칭(한국어/영어/축약)을 모두 받는다")
    func statusParse() {
        #expect(Decision.Status.parse("accepted") == .accepted)
        #expect(Decision.Status.parse("채택") == .accepted)
        #expect(Decision.Status.parse("확정") == .accepted)
        #expect(Decision.Status.parse("a") == .accepted)
        #expect(Decision.Status.parse("대체됨") == .superseded)
        #expect(Decision.Status.parse("버림") == .rejected)
        #expect(Decision.Status.parse("nonsense") == nil)
    }

    @Test("태그 파싱이 #, 공백, 콤마를 처리하고 중복을 없앤다")
    func tagParse() {
        #expect(TagParser.parse("#swift, sqlite  #ios") == ["swift", "sqlite", "ios"])
        #expect(TagParser.parse("a,,b") == ["a", "b"])
        #expect(TagParser.parse("dup, dup") == ["dup"])
        #expect(TagParser.parse("").isEmpty)
    }
}
