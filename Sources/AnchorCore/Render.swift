import Foundation

public enum Render {
    /// 목록 한 줄: 상태 배지 + 제목 + 프로젝트 + 태그 + 지난 시간
    public static func line(_ d: Decision, showProject: Bool = true) -> String {
        var parts = [Out.badge(d.status), Out.bold("#\(d.id)"), d.title]
        if showProject {
            parts.append(Out.cyan(d.project))
        }
        if !d.tags.isEmpty {
            parts.append(Out.blue(d.tags.map { "#\($0)" }.joined(separator: " ")))
        }
        parts.append(Out.dim(TimeParser.shortRelative(d.createdAt)))
        return parts.joined(separator: "  ")
    }

    /// 단일 결정 상세.
    public static func detail(_ d: Decision, alts: [Alternative], cwdIsSame: Bool) -> String {
        var s = ""
        s += "\(Out.bold("#\(d.id)  \(d.title)"))\n"
        s += "  \(Out.badge(d.status))  \(Out.cyan(d.project))  \(Out.dim(TimeParser.localString(d.createdAt)))\n"
        if !d.tags.isEmpty {
            s += "  \(Out.blue(d.tags.map { "#\($0)" }.joined(separator: " ")))\n"
        }
        s += "\n"
        if !d.context.isEmpty {
            s += "\(Out.dim("상황"))\n  \(indent(d.context))\n\n"
        }
        if !d.choice.isEmpty {
            s += "\(Out.dim("결정"))\n  \(indent(d.choice))\n\n"
        }
        if !alts.isEmpty {
            s += "\(Out.dim("기각한 대안"))\n"
            for a in alts {
                let mark = a.whyNot.isEmpty ? "" : "  \(Out.dim("→ \(a.whyNot)"))"
                s += "  • \(a.option)\(mark)\n"
            }
            s += "\n"
        }
        if !d.rejected.isEmpty {
            s += "\(Out.dim("버린 이유"))\n  \(indent(d.rejected))\n\n"
        }
        s += "\(Out.dim("수정: anchor edit \(d.id) \"새 제목\" · anchor set \(d.id) --status accepted"))"
        return s
    }

    /// 여러 줄 문자열을 2칸 들여쓰기.
    public static func indent(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  \($0)" }
            .joined(separator: "\n")
    }

    /// 회고 출력: 날짜 헤더 + 결정들.
    public static func retro(days: Int, project: String?, decisions: [Decision], retros: [Retro]) -> String {
        var s = ""
        let title = project.map { "\($0) · 최근 \(days)일" } ?? "전체 · 최근 \(days)일"
        s += Out.bold("회고  \(title)") + "\n"
        s += Out.dim(String(repeating: "─", count: 50)) + "\n"

        // 날짜별 그룹
        let cal = Calendar.current
        var groups: [Date: [Decision]] = [:]
        for d in decisions {
            let k = cal.startOfDay(for: d.createdAt)
            groups[k, default: []].append(d)
        }
        for k in groups.keys.sorted(by: >) {
            s += "\n" + Out.bold(TimeParser.dayLabel(k)) + "\n"
            for d in groups[k]! {
                s += "  " + line(d, showProject: project == nil) + "\n"
            }
        }

        if !retros.isEmpty {
            s += "\n" + Out.bold("작성한 회고 노트") + "\n"
            for r in retros {
                s += "  \(Out.dim(TimeParser.localString(r.createdAt)))  \(Out.bold(r.title))"
                if !r.mood.isEmpty { s += "  \(Out.yellow(r.mood))" }
                s += "\n"
                if !r.summary.isEmpty { s += indent(r.summary) + "\n" }
            }
        }

        // 자주 나온 태그
        var tagCount: [String: Int] = [:]
        for d in decisions { for t in d.tags { tagCount[t, default: 0] += 1 } }
        let top = tagCount.sorted { $0.value > $1.value }.prefix(5)
        if !top.isEmpty {
            s += "\n" + Out.dim("자주 나온 주제  ")
            s += top.map { Out.blue("#\($0.key)(\($0.value))") }.joined(separator: "  ") + "\n"
        }
        return s
    }

    /// 집계 출력. GUI 대시보드와 같은 Stats 를 그린다.
    public static func stats(_ s: Stats) -> String {
        var out = ""

        // 헤드라인
        out += Out.bold("\(s.streak)일 연속") + Out.dim("  ·  ") +
               Out.bold("\(s.thisWeek)건") + Out.dim(" 최근 7일  ·  ") +
               Out.bold("\(s.total)건") + Out.dim(" 전체") + "\n"

        // 주간 추세
        if s.weekTrend != 0 {
            let up = s.weekTrend > 0
            let mark = up ? "▲" : "▼"
            let color = up ? Out.green : Out.yellow
            out += Out.dim("  ") + color("\(mark) \(abs(s.weekTrend))") +
                   Out.dim(" 저번 주 대비") + "\n"
        }
        if let last = s.daysSinceLast {
            out += Out.dim("  마지막 기록 ") +
                   (last == 0 ? Out.green("오늘") : Out.dim("\(last)일 전")) + "\n"
        }

        // 일별 활동 바
        out += "\n" + Out.dim("최근 \(s.days.count)일  ") +
               activityBars(s.days, peak: s.peak) + "\n"

        // 상태 분포
        if !s.byStatus.isEmpty {
            out += "\n" + Out.dim("상태  ")
            for sc in s.byStatus {
                out += Out.dim("\(sc.status.label) \(sc.count)  ")
            }
            out += "\n"
        }

        // 자주 기록한 주제
        if !s.topTags.isEmpty {
            out += "\n" + Out.dim("자주 기록한 주제  ")
            out += s.topTags.map { Out.blue("#\($0.tag)(\($0.count))") }
                .joined(separator: "  ") + "\n"
        }
        return out
    }

    /// 일별 활동을 한 줄 막대로. 가장 최근 날이 오른쪽.
    private static func activityBars(_ days: [Stats.Day], peak: Int) -> String {
        guard peak > 0 else { return Out.dim("(기록 없음)") }
        let blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        var line = ""
        for d in days {
            if d.count == 0 {
                line += Out.dim("·")
            } else {
                // 0 은 최소 1칸(▁) 으로. 기록이 있다는 게 보이도록.
                let ratio = Double(d.count) / Double(peak)
                let idx = min(blocks.count - 1, max(0, Int(ratio * Double(blocks.count - 1))))
                line += Out.cyan(blocks[idx])
            }
        }
        return line
    }
}
