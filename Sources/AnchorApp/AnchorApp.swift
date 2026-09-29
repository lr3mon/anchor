import SwiftUI
import AppKit
import AnchorCore

/// 메뉴바 전용 앱 진입점.
/// NSApplication 을 직접 쓰므로 (RunFox 와 같은 방식) Xcode 프로젝트가 필요 없다.
/// LSUIElement = true 는 Scripts/package.py 가 만드는 Info.plist 에 들어간다.
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
            model.onChange = { [weak self] in self?.refreshStatusItem() }
            model.reload()
        } catch {
            // DB 를 못 열면 아무것도 못 하므로 조용히 종료하지 않는다.
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        // ── 메뉴바 ──
        // SF Symbol 대신 직접 그린 픽셀 아트 닻을 쓴다. Assets/AnchorMenuBar.iconset
        // 을 .icns 로 굽지 않고 NSImage 를 런타임에 그린다 (make_assets.py 와 같은 모양).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            let icon = MenuBarIcon.make(count: model.todayCount)
            icon.isTemplate = false   // 아래에서 직접 색을 칠한다
            btn.image = icon
            btn.target = self
            btn.action = #selector(toggle)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            refreshStatusItem()
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

    /// 메뉴바 아이콘을 현재 상태(오늘 기록 수)로 다시 그린다.
    private func refreshStatusItem() {
        guard let btn = statusItem.button else { return }
        let n = model.todayCount
        btn.image = MenuBarIcon.make(count: n)
        btn.toolTip = n > 0
            ? "anchor · 오늘 \(n)건"
            : "anchor · 오늘 기록 없음"
        btn.image?.isTemplate = false
        // 0 이면 숫자 없이 닻만, 있으면 닻 + 개수
        if n > 0 { statusItem.length = 34 } else { statusItem.length = 22 }
    }

    private func show() {
        guard let btn = statusItem.button else { return }
        model.reload()          // 열 때마다 최신 상태로
        refreshStatusItem()
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func close() {
        popover.performClose(nil)
    }

    /// 저장/삭제/상태변경 직후 호출. 메뉴바 숫자를 즉시 갱신한다.
    func notifyDataChanged() {
        refreshStatusItem()
    }
}
