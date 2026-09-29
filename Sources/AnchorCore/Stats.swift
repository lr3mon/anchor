import Foundation

/// 집계 결과. Store 의 SQL 을 그대로 화면에 노출하지 않고 여기서 모은다.
///
/// anchor 는 "결정을 얼마나 자주 하는가"가 곧 사용량이다. 그래서 기록 자체가
/// 곧 활동 기록이 되고, 별도 이벤트 테이블이 필요 없다.
public struct Stats: Sendable {
    /// 하루 단위 활동. 최근 `days` 일치, 날짜 오름차순. 없는 날은 0으로 채운다.
    public struct Day: Sendable, Identifiable {
        public var date: Date
        public var count: Int
        public var id: Date { date }

        public var isToday: Bool { Calendar.current.isDateInToday(date) }
    }

    public struct StatusCount: Sendable, Identifiable {
        public var status: Decision.Status
        public var count: Int
        public var id: String { status.rawValue }
    }

    public struct TagCount: Sendable, Identifiable {
        public var tag: String
        public var count: Int
        public var id: String { tag }
    }

    public var total: Int = 0
    public var days: [Day] = []
    public var byStatus: [StatusCount] = []
    public var topTags: [TagCount] = []
    /// 연속 기록 일수. 오늘 기록 안 했어도 어제부터 이어졌으면 유지된다.
    public var streak: Int = 0
    /// 마지막 기록 이후 지난 일수. 기록이 없으면 nil.
    public var daysSinceLast: Int?
    /// 최근 7일 합계 (오늘 포함).
    public var thisWeek: Int = 0
    /// 직전 7일 합계.
    public var lastWeek: Int = 0

    /// 이번 주가 저번 주보다 나아졌는지.
    public var weekTrend: Int { thisWeek - lastWeek }

    /// 일별 최대값. 히트맵 색 농도 기준.
    public var peak: Int { days.map(\.count).max() ?? 0 }

    public init() {}
}

public extension Store {
    /// 일/상태/태그 집계.
    /// - Parameter days: 최근 며칠을 볼지.
    /// - Parameter project: 특정 프로젝트로 좁히려면.
    func stats(days: Int = 30, project: String? = nil) throws -> Stats {
        var out = Stats()
        let cal = Calendar.current

        // 날짜 키는 항상 **로컬** 기준 yyyy-MM-dd 로 맞춘다.
        // created_at 은 UTC ISO8601 로 저장되므로 SQL 에서 로컬로 변환해야 하고,
        // 비교하는 Swift 쪽 키도 같은 타임존으로 만들어야 한다.
        // (한쪽만 UTC 면 자정 근처 기록이 하루 밀린다)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        fmt.locale = Locale(identifier: "en_US_POSIX")

        // WHERE 절을 조건 목록으로 만들어 중복을 피한다.
        var conds: [String] = []
        if let p = project { conds.append("project = \(p.sqlLiteral)") }
        let whereSQL = conds.isEmpty ? "" : " WHERE " + conds.joined(separator: " AND ")

        // ── 일별 활동 ──
        // date(created_at,'localtime') 가 UTC 문자열을 로컬 날짜로 바꿔준다.
        // substr 은 UTC 날짜라 자정 근처에서 하루씩 밀린다.
        let s = try query("""
            SELECT date(created_at, 'localtime') d, COUNT(*) c
            FROM decisions\(whereSQL)
            GROUP BY d ORDER BY d
            """)
        var counts: [String: Int] = [:]
        var total = 0
        while try s.next() {
            let d = s.colText(0) ?? ""
            let c = Int(s.colInt(1))
            counts[d] = c
            total += c
        }
        out.total = total

        // 최근 `days` 일짜 골라 0 채우기
        let today = cal.startOfDay(for: Date())
        var dayList: [Stats.Day] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = fmt.string(from: d)
            dayList.append(Stats.Day(date: d, count: counts[key] ?? 0))
        }
        out.days = dayList

        // ── 상태 분포 ──
        let s2 = try query("""
            SELECT status, COUNT(*) c FROM decisions\(whereSQL)
            GROUP BY status ORDER BY c DESC
            """)
        var statuses: [Stats.StatusCount] = []
        while try s2.next() {
            if let st = Decision.Status(rawValue: s2.colText(0) ?? "") {
                statuses.append(.init(status: st, count: Int(s2.colInt(1))))
            }
        }
        out.byStatus = statuses

        // ── 태그 빈도 ──
        // tags 는 "a, b" 형태의 한 컬럼이라 SQL 로 쪼개기 어렵다.
        // 전체를 읽고 Swift 에서 센다 (데이터가 수천 개 행 규모라 문제없음).
        // whereSQL 이 이미 WHERE 를 포함하므로 조건을 목록에 추가한다.
        var tagConds = conds
        tagConds.append("tags != ''")
        let tagWhere = " WHERE " + tagConds.joined(separator: " AND ")
        let s3 = try query("SELECT tags FROM decisions\(tagWhere)")
        var tagCounts: [String: Int] = [:]
        while try s3.next() {
            for t in (s3.colText(0) ?? "").split(separator: ",") {
                let key = t.trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { tagCounts[key, default: 0] += 1 }
            }
        }
        // 정렬 조건이 복잡한 삼항식은 컴파일러가 타입 추정에 오래 걸린다.
        // 비교 함수를 분리해 명시한다.
        let pairs = tagCounts.map { Stats.TagCount(tag: $0.key, count: $0.value) }
        var sorted = pairs
        sorted.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.tag < rhs.tag
        }
        out.topTags = Array(sorted.prefix(8))

        // ── 연속 기록 ──
        // 오늘 기록이 있으면 오늘부터, 없으면 어제부터 거슬러 올라간다.
        // "오늘 안 한 것"은 연속을 끊지 않는다 (어제까지 이어졌다면 유지).
        var streak = 0
        var cursor = today
        var maySkipToday = (counts[fmt.string(from: today)] ?? 0) == 0
        while true {
            if (counts[fmt.string(from: cursor)] ?? 0) > 0 {
                streak += 1
                maySkipToday = false
            } else if maySkipToday {
                // 오늘을 한 번 건너뛴다. 여기서도 비었으면 연속 종료.
                maySkipToday = false
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        out.streak = streak

        // ── 마지막 기록 시점 ──
        if let last = dayList.last(where: { $0.count > 0 }) {
            let diff = cal.dateComponents([.day], from: last.date, to: today).day ?? 0
            out.daysSinceLast = diff
        }

        // ── 주간 비교 ──
        out.thisWeek = dayList.suffix(7).reduce(0) { $0 + $1.count }
        out.lastWeek = dayList.dropLast(7).suffix(7).reduce(0) { $0 + $1.count }

        return out
    }
}

extension String {
    /// SQL 문자열 리터럴. 작은따옴표를 두 배로 늘린다.
    var sqlLiteral: String { "'" + replacingOccurrences(of: "'", with: "''") + "'" }
}
