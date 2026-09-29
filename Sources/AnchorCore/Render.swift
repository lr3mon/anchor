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
}
