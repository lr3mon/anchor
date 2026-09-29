import SwiftUI

/// 회고: 기간별 결정 묶음 + 빈도 높은 태그.
struct RetroView: View {
    @Bindable var model: AppModel
    @State private var days: Int = 7
    @State private var noteText: String = ""

    private var decisions: [Decision] {
        let since = TimeParser.daysAgoStart(days)
        return model.decisions.filter { $0.createdAt >= since }
    }

    private var grouped: [(Date, [Decision])] {
        let cal = Calendar.current
        var g: [Date: [Decision]] = [:]
        for d in decisions {
            g[cal.startOfDay(for: d.createdAt), default: []].append(d)
        }
        return g.keys.sorted(by: >).map { ($0, g[$0]!) }
    }

    private var topTags: [(String, Int)] {
        var c: [String: Int] = [:]
        for d in decisions { for t in d.tags { c[t, default: 0] += 1 } }
        return c.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 기간 선택
            HStack(spacing: 6) {
                Text("기간")
                Picker("", selection: $days) {
                    Text("7일").tag(7)
                    Text("30일").tag(30)
                    Text("90일").tag(90)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 90)
                Spacer()
                Text("\(decisions.count)건")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !topTags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("자주 나온 주제")
                                .font(.system(size: 11, weight: .semibold))
                            HStack(spacing: 5) {
                                ForEach(topTags, id: \.0) { tag, n in
                                    Text("#\(tag) \(n)")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    ForEach(grouped, id: \.0) { day, items in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(TimeParser.dayLabel(day))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            ForEach(items) { d in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(d.status == .accepted ? Color.green : Color.gray)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 4)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.title).font(.system(size: 12))
                                        if !d.choice.isEmpty {
                                            Text(d.choice)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    if decisions.isEmpty {
                        Text("이 기간에 기록한 결정이 없습니다")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                }
                .padding(12)
            }

            Divider()

            // 회고 노트
            HStack(spacing: 6) {
                TextField("회고 한 줄 (선택)", text: $noteText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button("남기기") {
                    guard !noteText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    try? model.store.addRetro(Retro(
                        id: 0,
                        project: model.currentProject ?? "unknown",
                        title: noteText.trimmingCharacters(in: .whitespaces),
                        summary: "", mood: "", createdAt: Date()))
                    noteText = ""
                }
                .controlSize(.small)
                .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }
}
