import SwiftUI
import AnchorCore

/// 새 결정 기록 폼. "기각한 대안"을 여러 줄 직접 넣게 한다.
struct NewDecisionForm: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                field("무엇을 정했나", required: true) {
                    TextField("예: 결정 로그를 SQLite로 옮김", text: $model.draftTitle)
                        .textFieldStyle(.roundedBorder)
                }

                field("무슨 상황이어서") {
                    TextField("예: JSON 파일이 병합이 안 돼서 충돌남",
                              text: $model.draftContext, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }

                field("결정") {
                    TextField("예: system libsqlite3 직접 사용",
                              text: $model.draftChoice, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }

                // ── 대안 ──
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("기각한 대안")
                            .font(.system(size: 11, weight: .semibold))
                        Text("왜 안 했는지가 핵심")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.draftAlternatives.append(.init())
                        } label: {
                            Image(systemName: "plus.circle").font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("대안 추가")
                    }

                    ForEach($model.draftAlternatives) { $alt in
                        HStack(alignment: .top, spacing: 5) {
                            TextField("옵션", text: $alt.option)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            TextField("왜 안 했나", text: $alt.whyNot)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            Button {
                                model.draftAlternatives.removeAll { $0.id == alt.id }
                                if model.draftAlternatives.isEmpty {
                                    model.draftAlternatives = [.init()]
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                field("태그") {
                    TextField("쉼표로 구분, 예: sqlite, decision-log",
                              text: $model.draftTags)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                HStack {
                    Text("현재 프로젝트: \(model.currentProject ?? "자동 감지 실패")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("취소") { model.resetForm() }
                        .keyboardShortcut(.cancelAction)
                    Button("저장") { model.saveDraft() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canSave)
                }
            }
            .padding(12)
        }
    }

    private func field<C: View>(_ label: String, required: Bool = false,
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11, weight: .semibold))
                if required {
                    Text("필수").font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
            content()
        }
    }
}
