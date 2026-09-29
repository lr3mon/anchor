import SwiftUI
import AnchorCore

/// 대시보드: 최근 활동 히트맵 + 스파크라인 + 지표.
///
/// RunFox 가 CPU 를 그래프로 보여주듯, anchor 는 결정 활동량을 보여준다.
/// 기록 자체가 곧 사용량이므로 별도 이벤트를 쌓을 필요가 없다.
struct DashboardView: View {
    let stats: Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            metricRow
            heatmap
            if !stats.byStatus.isEmpty {
                statusBar
            }
            if !stats.topTags.isEmpty {
                tagCloud
            }
        }
    }

    // MARK: - 지표

    private var metricRow: some View {
        HStack(spacing: 0) {
            metric(
                value: "\(stats.streak)",
                unit: "일",
                label: "연속 기록",
                tint: stats.streak > 0 ? .accentColor : .secondary
            )
            divider
            metric(
                value: "\(stats.thisWeek)",
                unit: "건",
                label: "최근 7일",
                tint: .primary,
                delta: stats.weekTrend
            )
            divider
            metric(
                value: "\(stats.total)",
                unit: "건",
                label: "전체",
                tint: .primary
            )
        }
        .padding(.vertical, 2)
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 30)
    }

    private func metric(value: String, unit: String, label: String,
                        tint: Color, delta: Int? = nil) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if let d = delta, d != 0 {
                    Image(systemName: d > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(d > 0 ? Color.green : Color.orange)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 히트맵

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("최근 \(stats.days.count)일")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = stats.daysSinceLast {
                    Text(last == 0 ? "오늘 기록함" : "\(last)일 전 마지막 기록")
                        .font(.system(size: 10))
                        .foregroundStyle(last <= 2 ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                }
            }
            // 고정 높이를 주지 않는다. 히트맵은 7행 x 10pt + 간격이라 약 88pt 이고,
            // height 를 강제로 하면 라벨과 겹친다.
            ActivityHeatmap(days: stats.days, peak: stats.peak)
        }
    }

    // MARK: - 상태 분포

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("상태")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            // 한 줄 스택 바. 전체 넓이를 비율로 채운다.
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(stats.byStatus) { sc in
                        let w = geo.size.width * CGFloat(sc.count) / CGFloat(max(1, stats.total))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: sc.status))
                            .frame(width: max(2, w))
                    }
                }
            }
            .frame(height: 7)
            HStack(spacing: 9) {
                ForEach(stats.byStatus) { sc in
                    HStack(spacing: 3) {
                        Circle().fill(color(for: sc.status)).frame(width: 5, height: 5)
                        Text("\(sc.status.label) \(sc.count)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func color(for s: Decision.Status) -> Color {
        switch s {
        case .accepted:  return .green
        case .proposed:  return .blue
        case .superseded: return .orange
        case .rejected:  return .secondary
        }
    }

    // MARK: - 태그

    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("자주 기록한 주제")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            // Wrap 은 iOS 16+/macOS 13+ 에 있지만 LazyVGrid 로 안전하게 감싼다.
            FlowLayout(spacing: 4) {
                ForEach(stats.topTags) { t in
                    HStack(spacing: 3) {
                        Text(t.tag)
                            .font(.system(size: 10, weight: .medium))
                        Text("\(t.count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(min(0.28, 0.07 + Double(t.count) * 0.045)))
                    )
                    .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// 달력형 활동 히트맵. 최근 N 일을 세로 열(각 열 = 1주)로 그린다.
///
/// RunFox 의 3x10 히트맵처럼 행을 요일로 맞추면 눈으로 읽히지만, 화면 폭이 400pt
/// 라 주 단위로 돌려 읽는 게 더 자연스럽다. 오른쪽 끝이 항상 오늘.
struct ActivityHeatmap: View {
    let days: [Stats.Day]
    let peak: Int

    private let cell: CGFloat = 10
    private let gap: CGFloat = 3

    var body: some View {
        // 7일이 한 열. 오래된 날이 왼쪽, 오늘이 오른쪽.
        let columns = stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        if row < col.count {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(col[row].count))
                                .frame(width: cell, height: cell)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(_ n: Int) -> Color {
        guard n > 0, peak > 0 else { return Color.secondary.opacity(0.14) }
        let ratio = Double(n) / Double(peak)
        // 0.30 -> 0.95. 최소값을 충분히 주어 "기록 있음"이 확실히 보인다.
        let a = 0.30 + min(1.0, ratio) * 0.65
        return Color.accentColor.opacity(a)
    }
}

/// 간단한 줄바 배치. 태그 칩처럼 크기가 제각각인 걸 흐르게 한다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
