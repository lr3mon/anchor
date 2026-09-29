# anchor — GUI

macOS 메뉴바에서 쓰는 결정 기록 앱. CLI 와 같은 DB(`~/.anchor/decisions.db`)를 공유하므로
GUI 로 기록하고 터미널로 조회하는 식으로 섞어 쓸 수 있습니다.

## 설치 / 빌드

```bash
# 앱만 빌드하고 ~/Applications 에 설치
python3 Scripts/package.py --install

# 버전 지정 + 배포 zip 생성
python3 Scripts/package.py --version 0.2.0
# → dist/Anchor.app, dist/Anchor-0.2.0-macOS-arm64.zip
```

`open -a Anchor` 로 실행. Dock 에는 안 뜨고 메뉴바 오른쪽에 닻 아이콘만 남습니다.
아이콘을 클릭하면 팝오버 패널이 열립니다.

## Xcode 프로젝트가 없는 이유

SwiftPM 은 `.app` 번들을 만들지 못합니다. 하지만 **Xcode 프로젝트가 필요하지는 않습니다.**

`Scripts/package.py` 가 SwiftPM 으로 만든 바이너리를 `Contents/` 구조에 직접 조립하고
Info.plist 를 쓰고 ad-hoc 서명합니다. 이 방식이 GitHub Actions 에서 그대로 돌아가므로
앱도 자동 배포할 수 있습니다. (Xcode 프로젝트를 썼다면 앱 빌드는 로컬 전용이 됩니다.)

RunFox 가 쓰는 방식과 같습니다.

## 메뉴바 아이콘

SF Symbol 대신 닻을 직접 픽셀로 그립니다 (`Sources/AnchorApp/MenuBarIcon.swift`).
`Scripts/make_assets.py` 의 `anchor_sprite()` 와 같은 12x14 격자입니다.

- 오늘 기록 0건: 닻만, 회색
- 오늘 기록 있음: 닻 + 개수, 강조색

저장/삭제/상태변경 시 `AppModel.onChange` → `refreshStatusItem()` 로 즉시 갱신됩니다.

## 기능

- **기록** — `+` 버튼. 제목(필수) / 상황 / 결정 / 기각한 대안 / 태그
- **읽기** — 목록에서 행을 누르면 상황·대안·상태가 펼쳐짐
- **회고** — 시계 아이콘. 기간별 결정 묶음 + 자주 나온 주제
- **상태 변경** — 펼친 상태에서 드롭다운으로 accepted/proposed/superseded/rejected
- **삭제** — 펼친 상태의 휴지통 버튼

## 프로젝트 자동 감지

앱을 띄운 위치의 git 저장소를 자동 감지해 그 프로젝트로 기록합니다.
하위 디렉터리에서 실행해도 루트 저장소가 잡힙니다. 드롭다운에서 직접 고를 수도 있고
"전체"로 모든 프로젝트를 볼 수 있습니다.

## 구조

```
Sources/
├── AnchorCore/    로직 (Store/Database/Model/Render) — CLI 와 앱이 공유
├── Anchor/        CLI 진입점
└── AnchorApp/
    ├── main.swift          NSApplication 진입점 (@main 아님)
    ├── AnchorApp.swift     AppDelegate, NSPopover, 상태아이콘
    ├── MenuBarIcon.swift   닻 픽셀 아트 렌더러
    ├── AppModel.swift      @Observable 상태
    ├── MenuBarView.swift   패널 골격
    ├── NewDecisionForm.swift  기록 폼
    ├── DecisionRow.swift      목록 행
    └── RetroView.swift        회고
Scripts/
├── make_assets.py   앱 아이콘(.icns) 생성 — PIL 픽셀 아트
└── package.py       .app 번들 조립 + ad-hoc 서명 + zip
```

`AnchorApp` 는 `AnchorCore` 를 `import` 한다. Xcode 프로젝트로 묶지 않으므로
일반 SwiftPM 모듈 경계를 그대로 쓴다.

## 검증 모드

```bash
APP=dist/Anchor.app/Contents/MacOS/Anchor

# 창을 띄워서 레이아웃 확인 (메뉴바 대신 일반 창)
ANCHOR_UI_TEST=1 "$APP"

# 저장 경로만 검증하고 종료 (창 조작 없이 AppModel.saveDraft 실행)
cd ~/projects/개인/SaaS·앱/anchor
ANCHOR_SELFTEST=1 ANCHOR_SELFTEST_DB=/tmp/t.db "$APP"

# 교차 검증
anchor --db /tmp/t.db show 1
```

## 주의

- 앱을 다른 저장소에서 기록하려면 **그 저장소 디렉터리에서 실행**해야 프로젝트가
  제대로 잡힙니다. Dock 에서 실행하면 마지막 프로젝트로 기록됩니다.
- `testPanel` 은 반드시 strong reference 로 유지해야 합니다. 지역변수로 두면 ARC 가
  dealloc 하면서 AppKit 애니메이션 중 over-release 크래시가 납니다.
- ad-hoc 서명이라 다른 Mac 으로 옮기면 Gatekeeper 가 물을 수 있습니다. 배포용으로는
  Apple Developer 서명이 필요합니다.
