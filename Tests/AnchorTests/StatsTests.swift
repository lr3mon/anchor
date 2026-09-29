import Testing
import Foundation
@testable import AnchorCore

@Suite("Stats — 집계")
struct StatsTests {

    private func tempStore() throws -> (Store, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anchor-stats-\(UUID().uuidString)")
        let db = dir.appendingPathComponent("t.db")
        return (try Store(path: db.path), dir)
    }

    /// n 일 전의 날짜. created_at 이 ISO8601 문자열이라 날짜만 중요하다.
    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    @discardableResult
    private func add(_ s: Store, daysAgo n: Int, title: String,
                     status: Decision.Status = .accepted,
                     tags: String = "") throws -> Int64 {
        // created_at 이 n 일 전이어야 streak/일별 집계가 의미를 가진다.
        let d = daysAgo(n)
        return try s.addDecision(Decision(
            id: 0, project: "p", title: title, context: "", choice: "",
            rejected: "", status: status, tags: TagParser.parse(tags),
            createdAt: d, updatedAt: d))
    }

    @Test("빈 DB 에서 total 0이고 streak 0이다")
    func empty() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let st = try s.stats(days: 28)
        #expect(st.total == 0)
        #expect(st.streak == 0)
        #expect(st.daysSinceLast == nil)
        #expect(st.days.count == 28)
    }

    @Test("days 배열은 항상 요청한 길이이고 0으로 채워진다")
    func daysFilled() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 0, title: "오늘")
        let st = try s.stats(days: 14)
        #expect(st.days.count == 14)
        // 마지막 칸이 오늘이고 count 1 이어야 한다.
        #expect(st.days.last?.isToday == true)
        #expect(st.days.last?.count == 1)
        // 전체 합이 total 과 같아야 한다.
        #expect(st.days.reduce(0) { $0 + $1.count } == st.total)
    }

    @Test("오늘 기록하면 streak 이 1 이다")
    func streakToday() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 0, title: "오늘")
        #expect(try s.stats(days: 28).streak == 1)
    }

    @Test("연속 3일이면 streak 3 이다")
    func streakThree() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 0, title: "d0")
        try add(s, daysAgo: 1, title: "d1")
        try add(s, daysAgo: 2, title: "d2")
        let st = try s.stats(days: 28)
        #expect(st.streak == 3)
    }

    @Test("어제 끊기면 streak 이 끊긴다")
    func streakBroken() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 0, 1, 3일 전. 2일 전이 비어 있으므로 streak 은 2 까지만.
        try add(s, daysAgo: 0, title: "d0")
        try add(s, daysAgo: 1, title: "d1")
        try add(s, daysAgo: 3, title: "d3")
        #expect(try s.stats(days: 28).streak == 2)
    }

    @Test("오늘 기록이 없어도 어제부터 이어진 streak 이 유지된다")
    func streakFromYesterday() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 1, title: "y")
        try add(s, daysAgo: 2, title: "d2")
        let st = try s.stats(days: 28)
        #expect(st.streak == 2)
        #expect(st.daysSinceLast == 1)
    }

    @Test("어제도 비었으면 streak 0 이다")
    func streakDead() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 5, title: "오래 전")
        let st = try s.stats(days: 28)
        #expect(st.streak == 0)
        #expect(st.daysSinceLast == 5)
    }

    @Test("상태 분포가 파싱된다")
    func statusBreakdown() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 0, title: "a", status: .accepted)
        try add(s, daysAgo: 0, title: "b", status: .accepted)
        try add(s, daysAgo: 1, title: "c", status: .rejected)
        let st = try s.stats(days: 28)
        #expect(st.total == 3)
        let acc = st.byStatus.first { $0.status == .accepted }
        let rej = st.byStatus.first { $0.status == .rejected }
        #expect(acc?.count == 2)
        #expect(rej?.count == 1)
    }

    @Test("태그 빈도가 내림차순으로 온다")
    func tagRanking() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try add(s, daysAgo: 0, title: "a", tags: "swift, db")
        try add(s, daysAgo: 1, title: "b", tags: "swift")
        try add(s, daysAgo: 2, title: "c", tags: "swift, gui")
        let st = try s.stats(days: 28)
        #expect(st.topTags.first?.tag == "swift")
        #expect(st.topTags.first?.count == 3)
        // 나머지는 개수 내림차순
        let counts = st.topTags.map(\.count)
        #expect(counts == counts.sorted(by: >))
    }

    @Test("프로젝트를 지정하면 그 프로젝트만 집계한다")
    func projectFilter() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        try s.addDecision(Decision(id: 0, project: "alpha", title: "a", context: "",
                                   choice: "", rejected: "", status: .accepted, tags: [],
                                   createdAt: now, updatedAt: now))
        try s.addDecision(Decision(id: 0, project: "beta", title: "b", context: "",
                                   choice: "", rejected: "", status: .accepted, tags: [],
                                   createdAt: now, updatedAt: now))
        #expect(try s.stats(days: 28, project: "alpha").total == 1)
        #expect(try s.stats(days: 28, project: nil).total == 2)
    }

    @Test("아포스트로피가 들어간 프로젝트명도 깨지지 않는다")
    func sqlInjectionSafe() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let evil = "x'; DROP TABLE decisions; --"
        let now = Date()
        try s.addDecision(Decision(id: 0, project: evil, title: "t", context: "",
                                   choice: "", rejected: "", status: .accepted, tags: [],
                                   createdAt: now, updatedAt: now))
        // 드롭되지 않았고 집계도 되야 한다.
        #expect(try s.stats(days: 28, project: evil).total == 1)
        #expect(try s.count(Store.Filter()) == 1)
    }

    @Test("thisWeek / lastWeek 비교가 맞는다")
    func weekCompare() throws {
        let (s, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 이번 주(주말 제외 최근 7일)에 3건, 직전 7일에 1건
        try add(s, daysAgo: 0, title: "w0")
        try add(s, daysAgo: 2, title: "w2")
        try add(s, daysAgo: 4, title: "w4")
        try add(s, daysAgo: 9, title: "l9")
        let st = try s.stats(days: 28)
        #expect(st.thisWeek == 3)
        #expect(st.lastWeek == 1)
        #expect(st.weekTrend == 2)
    }
}
