import SwiftUI
import AppKit
import AnchorCore

/// 메뉴바 아이콘 + 팝오버 진입점.
struct MenuBarView: View {
    @Bindable var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isFormOpen {
                NewDecisionForm(model: model)
            } else if model.isRetroOpen {
                RetroView(model: model)
            } else {
                listView
            }
        }
        .frame(width: 400, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { model.currentProject ?? "전체" },
                set: { model.currentProject = ($0 == "전체" ? nil : $0); model.refreshList() }
            )) {
                Text("전체").tag("전체")
                ForEach(model.projects, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 170)

            if !model.isFormOpen {
                TextField("검색", text: Binding(
                    get: { model.filterText },
                    set: { model.filterText = $0; model.refreshList() }
                ))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            }

            Spacer(minLength: 0)

            Button {
                if model.isFormOpen {
                    model.isFormOpen = false
                } else {
                    model.isFormOpen = true
                    model.isRetroOpen = false
                }
            } label: {
                Image(systemName: model.isFormOpen ? "xmark" : "plus")
            }
            .buttonStyle(.borderless)
            .help(model.isFormOpen ? "닫기" : "새 결정")

            Button {
                model.isRetroOpen.toggle()
                if model.isRetroOpen { model.isFormOpen = false }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("회고")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - 목록

    private var listView: some View {
        VStack(spacing: 0) {
            if model.decisions.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("결정 기록이 없습니다")
                        .foregroundStyle(.secondary)
                    Button("첫 결정 남기기") { model.isFormOpen = true }
                        .controlSize(.small)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.decisions) { d in
                            DecisionRow(d: d,
                                        alts: model.alternativesByDecision[d.id] ?? [],
                                        isExpanded: model.detailID == d.id,
                                        onToggle: {
                                            model.detailID = model.detailID == d.id ? nil : d.id
                                        },
                                        onStatus: { model.setStatus(d.id, $0) },
                                        onDelete: { model.remove(d.id) })
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("\(model.decisions.count)건")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let e = model.errorMessage {
                    Text(e).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
                Button("터미널로 열기") {
                    // CLI 이 쓰는 같은 DB 를 연다.
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/"))
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("터미널에서 anchor 명령어 사용")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}
