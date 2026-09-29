import SwiftUI
import AppKit
import AnchorCore

/// 메뉴바 앱 전역 상태.
/// SwiftUI @Observable 로 관찰하되, Store(DDL/SQLite) 접근은 여기서만 한다.
@MainActor
@Observable
final class AppModel {
    var store: Store!
    var decisions: [Decision] = []
    var projects: [String] = []
    var currentProject: String?
    var errorMessage: String?
    var filterText: String = ""

    // 기록 폼
    var draftTitle: String = ""
    var draftContext: String = ""
    var draftChoice: String = ""
    var draftRejected: String = ""
    var draftTags: String = ""
    var draftAlternatives: [AltDraft] = [AltDraft()]

    struct AltDraft: Identifiable, Sendable {
        var id = UUID()
        var option: String = ""
        var whyNot: String = ""
    }

    var isFormOpen = false
    var isRetroOpen = false
    var detailID: Int64?

    /// 오늘 기록한 결정 수. 메뉴바 아이콘에 숫자로 보여준다.
    var todayCount: Int {
        let cal = Calendar.current
        return decisions.filter { cal.isDateInToday($0.createdAt) }.count
    }

    init(store: Store) {
        self.store = store
    }

    /// 집계. 대시보드와 메뉴바 아이콘이 함께 쓴다.
    var stats = Stats()

    /// 데이터가 바뀔 때 호출. 메뉴바 아이콘 숫자 갱신용.
    var onChange: (() -> Void)?

    private func changed() {
        onChange?()
    }

    // MARK: - 로드

    func reload() {
        do {
            // 앱이 시작된 위치(작업 디렉터리) 기준으로 git 저장소를 찾는다.
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let detected = ProjectRef.detect(cwd: cwd)?.name
            let known = try store.projects()
            // 감지된 프로젝트에 실제 기록이 있을 때만 기본 선택한다.
            // (기록 없는 디렉터리에서 띄우면 목록이 비어 보이기 때문)
            projects = known
            let usable = detected.flatMap { known.contains($0) ? $0 : nil }
            currentProject = usable ?? known.first
            refreshList()
            refreshStats()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func refreshStats() {
        do {
            stats = try store.stats(days: 28, project: nil)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func refreshList() {
        do {
            var f = Store.Filter(limit: 50)
            if let p = currentProject { f.project = p }
            if !filterText.isEmpty { f.search = filterText }
            decisions = try store.list(f)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    var alternativesByDecision: [Int64: [Alternative]] {
        get {
            var map: [Int64: [Alternative]] = [:]
            for d in decisions {
                map[d.id] = (try? store.alternatives(decisionID: d.id)) ?? []
            }
            return map
        }
    }

    // MARK: - 기록

    var canSave: Bool { !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty }

    func saveDraft() {
        guard canSave else { return }
        do {
            let now = Date()
            let d = Decision(
                id: 0,
                project: currentProject ?? "unknown",
                title: draftTitle.trimmingCharacters(in: .whitespaces),
                context: draftContext,
                choice: draftChoice,
                rejected: draftRejected,
                status: .accepted,
                tags: TagParser.parse(draftTags),
                createdAt: now, updatedAt: now)
            let id = try store.addDecision(d)
            let alts = draftAlternatives
                .filter { !$0.option.trimmingCharacters(in: .whitespaces).isEmpty }
                .enumerated()
                .map { i, a in
                    Alternative(id: 0, decisionID: id,
                                option: a.option.trimmingCharacters(in: .whitespaces),
                                whyNot: a.whyNot, rank: i + 1)
                }
            if !alts.isEmpty { try store.addAlternatives(alts, decisionID: id) }
            resetForm()
            reload()
            changed()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func resetForm() {
        draftTitle = ""; draftContext = ""; draftChoice = ""
        draftRejected = ""; draftTags = ""
        draftAlternatives = [AltDraft()]
        isFormOpen = false
    }

    func remove(_ id: Int64) {
        do { try store.deleteDecision(id); reload(); changed() }
        catch { errorMessage = String(describing: error) }
    }

    func setStatus(_ id: Int64, _ status: Decision.Status) {
        do {
            guard var d = try store.decision(id: id) else { return }
            d.status = status
            d.updatedAt = Date()
            try store.updateDecision(d)
            reload()
            changed()
        } catch { errorMessage = String(describing: error) }
    }
}
