import Foundation

/// Swift 6 은 전역 공유 상태를 금지하므로(Strict Concurrency) formatter 를
/// 인스턴스로 만들어 넘긴다. 쓰레드도 안전하고 비용도 무시할 만하다.
public enum TimeParser {
    public static func makeISO() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    public static func makeLocal() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }

    /// 저장 형식: 초 단위 ISO8601 UTC ("2026-09-29T03:12:44Z")
    public static func nowString() -> String { makeISO().string(from: Date()) }
    public static func isoString(_ d: Date) -> String { makeISO().string(from: d) }
    public static func date(fromISO s: String) -> Date? { makeISO().date(from: s) }
    public static func localString(_ d: Date) -> String { makeLocal().string(from: d) }

    /// "7d", "3m", "2y" 같은 짧은 상대 표기 — 목록에서 빠르게 읽히도록.
    public static func shortRelative(_ date: Date, from now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        switch s {
        case ..<0:      return "미래"
        case ..<60:     return "방금"
        case ..<3600:   return "\(s / 60)m"
        case ..<86_400: return "\(s / 3600)h"
        case ..<604_800: return "\(s / 86_400)d"
        default:        return localString(date)
        }
    }

    /// 오늘/어제/지난 N일 같은 그룹 헤더용 라벨.
    public static func dayLabel(_ date: Date, from now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days <= 7 { return "\(days)일 전" }
        return makeLocal().string(from: date)
    }

    /// 최근 N일치 시작 시각 (회고 범위 계산).
    public static func daysAgoStart(_ days: Int, from now: Date = Date()) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: -max(0, days - 1), to: start) ?? start
    }
}
