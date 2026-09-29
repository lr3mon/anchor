import SwiftUI
import AppKit

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

    init(store: Store) {
        self.store = store
    }

    // MARK: - 로드

    func reload() {
        do {
            // 앱이 시작된 위치(작업 디렉터리) 기준으로 git 저장소를 찾는다.
            // 사용자는 앱을 어느 저장소에서 띄우든 그 프로젝트로 기록되길 원한다.
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let detected = ProjectRef.detect(cwd: cwd)?.name
            projects = (try store.projects()).sorted()
            // 감지된 프로젝트가 목록에 없으면 새 프로젝트로 추가한다.
            if let d = detected, !projects.contains(d) { projects.append(d) }
            if !projects.isEmpty { projects.sort() }
            currentProject = detected ?? currentProject ?? projects.first
            refreshList()
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
        do { try store.deleteDecision(id); reload() }
        catch { errorMessage = String(describing: error) }
    }

    func setStatus(_ id: Int64, _ status: Decision.Status) {
        do {
            guard var d = try store.decision(id: id) else { return }
            d.status = status
            d.updatedAt = Date()
            try store.updateDecision(d)
            reload()
        } catch { errorMessage = String(describing: error) }
    }
}
