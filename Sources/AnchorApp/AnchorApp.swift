import SwiftUI
import AppKit

// 앱 타깃은 AnchorCore 소스를 함께 컴파일하므로(같은 Sources phase),
// AnchorCore 는 독립 모듈이 아니다. 따라서 import AnchorCore 는 두지 않고
// Store/Decision/TimeParser 같은 심볼을 소스 레벨에서 그대로 쓴다.

/// 메뉴바 전용 앱 진입점.
/// LSUIElement = true 로 Dock 에는 안 뜨고 메뉴바 아이콘만 남는다.
@main
struct AnchorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 메뉴바 앱이라 표준 창/메뉴는 쓰지 않는다. 실제 UI 는 AppDelegate 가
        // NSPopover 로 직접 띄운다 (SwiftUI Scene 없이 동작).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var popover: NSPopover!
    private var statusItem: NSStatusItem!
    private var model: AppModel!
    /// UI 테스트 모드 창. 지역변수로 두면 ARC 가 dealloc 하면서
    /// AppKit 애니메이션 중 over-release 크래시가 난다. 반드시 유지한다.
    private var testPanel: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            model = AppModel(store: try Store.open())
            model.reload()
        } catch {
            // DB 를 못 열면 아무것도 못 하므로 조용히 종료하지 않는다.
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        // ── 메뉴바 ──
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "anchor", accessibilityDescription: "anchor")
            btn.image?.isTemplate = true
            btn.target = self
            btn.action = #selector(toggle)
        }

        // ── 팝오버 ──
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 400, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(model: model))

        // 메뉴바를 쓰므로 accessory 만 남긴다.
        NSApp.setActivationPolicy(.accessory)

        // UI 검증용: ANCHOR_UI_TEST=1 로 띄우면 메뉴바 아이콘 대신
        // 실제 패널을 창으로 연다. 스크린샷으로 레이아웃을 확인할 때 쓴다.
        if ProcessInfo.processInfo.environment["ANCHOR_UI_TEST"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let panel = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 400, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            panel.title = "anchor (UI test)"
            panel.contentView = NSHostingView(rootView: MenuBarView(model: model))
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            testPanel = panel   // 지역변수 스코프가 끝나도 살아있도록 유지
        }

        // 저장 경로 검증: ANCHOR_SELFTEST=1 이면 폼 입력 → 저장을 실제로 실행하고
        // 결과를 stdout 에 찍은 뒤 종료한다. 창 조작 없이 AppModel.saveDraft 를
        // 검증하므로 자동화에서 리liable 하다.
        if ProcessInfo.processInfo.environment["ANCHOR_SELFTEST"] == "1" {
            runSelfTest()
            return
        }
    }

    /// GUI 저장 경로 스모크 테스트.
    private func runSelfTest() {
        let db = ProcessInfo.processInfo.environment["ANCHOR_SELFTEST_DB"] ?? ":memory:"
        do {
            let s = try Store(path: db)
            let m = AppModel(store: s)
            m.currentProject = "anchor"
            m.reload()

            // 폼을 "사용자가 채운 상태"로 만든다.
            m.draftTitle = "GUI 저장 경로 검증"
            m.draftContext = "메뉴바에서 입력하는 상황"
            m.draftChoice = "AppModel.saveDraft 를 쓴다"
            m.draftTags = "#gui, #selftest"
            m.draftAlternatives = [
                .init(),   // 빈 행이 있어도 저장돼야 한다
                .init()
            ]
            m.draftAlternatives[1].option = "CLI 로만 기록"
            m.draftAlternatives[1].whyNot = "가장 느림"

            guard m.canSave else {
                print("SELFTEST FAIL: canSave 가 false (제목이 들어갔는데)")
                NSApp.terminate(nil); return
            }
            m.saveDraft()

            let rows = try s.list(Store.Filter(limit: 10))
            guard let saved = rows.first else {
                print("SELFTEST FAIL: 저장된 행이 없음")
                NSApp.terminate(nil); return
            }
            let alts = try s.alternatives(decisionID: saved.id)
            print("SELFTEST OK")
            print("  id=\(saved.id) title=\(saved.title)")
            print("  project=\(saved.project) (expected: \(m.currentProject ?? "nil"))")
            print("  tags=\(saved.tags)")
            print("  context=\(saved.context)")
            print("  choice=\(saved.choice)")
            print("  alternatives=\(alts.count)")
            for a in alts { print("    - \(a.option) → \(a.whyNot)") }
            print("  form_cleared=\(m.draftTitle.isEmpty)")
            print("  total_rows=\(rows.count)")
        } catch {
            print("SELFTEST ERROR: \(error)")
        }
        NSApp.terminate(nil)
    }

    @objc private func toggle() {
        if popover.isShown {
            close()
        } else {
            show()
        }
    }

    private func show() {
        guard let btn = statusItem.button else { return }
        model.reload()          // 열 때마다 최신 상태로
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func close() {
        popover.performClose(nil)
    }
}
