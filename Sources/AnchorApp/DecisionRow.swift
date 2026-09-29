import SwiftUI
import AnchorCore

/// 목록 한 행. 클릭하면 접혀 있던 상황/대안이 펼쳐진다.
struct DecisionRow: View {
    let d: Decision
    let alts: [Alternative]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onStatus: (Decision.Status) -> Void
    let onDelete: () -> Void

    @State private var hoverDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 한 줄 요약 ──
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    statusDot
                    Text(d.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if !d.tags.isEmpty {
                        Text(d.tags.prefix(2).map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                    Text(TimeParser.shortRelative(d.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── 펼침 ──
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !d.context.isEmpty {
                        field("상황", d.context)
                    }
                    if !d.choice.isEmpty {
                        field("결정", d.choice)
                    }
                    if !alts.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("기각한 대안")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(alts) { a in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("·").foregroundStyle(.secondary)
                                    Text(a.option).font(.system(size: 11))
                                    if !a.whyNot.isEmpty {
                                        Text("→ \(a.whyNot)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Text("상태")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { d.status },
                            set: { onStatus($0) }
                        )) {
                            ForEach(Decision.Status.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.mini)
                        .frame(width: 90)

                        Spacer()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .opacity(hoverDelete ? 1 : 0.4)
                        .onHover { hoverDelete = $0 }
                        .help("삭제")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
    }

    private func field(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .textSelection(.enabled)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private var color: Color {
        switch d.status {
        case .accepted:   return .green
        case .proposed:   return .yellow
        case .superseded: return .gray
        case .rejected:   return .red
        }
    }
}
