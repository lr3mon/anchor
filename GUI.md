# anchor — GUI

macOS 메뉴바에 떠서 쓰는 결정 기록 앱. CLI 와 같은 DB(`~/.anchor/decisions.db`)를
공유하므로 GUI 로 기록하고 터미널로 조회하는 식으로 섞어 쓸 수 있다.

## 빌드 & 실행

```bash
# 빌드
xcodebuild -project AnchorApp.xcodeproj -scheme AnchorApp \
           -configuration Release build

# 실행
open ~/Library/Developer/Xcode/DerivedData/AnchorApp-*/Build/Products/Release/Anchor.app
```

`open` 으로 띄우면 Dock 에는 안 뜨고 메뉴바 오른쪽에 앵커 아이콘만 생깁니다.
아이콘을 클릭하면 팝오버 패널이 열립니다.

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
└── AnchorApp/     SwiftUI 메뉴바 앱
    ├── AnchorApp.swift   진입점, NSPopover, 상태아이콘
    ├── AppModel.swift    @Observable 상태
    ├── MenuBarView.swift 패널 골격
    ├── NewDecisionForm.swift  기록 폼
    ├── DecisionRow.swift 목록 행
    └── RetroView.swift  회고
```

앱 타깃은 `AnchorCore` 소스를 함께 컴파일하므로 같은 타깃 안에서 심볼을 직접 쓴다.
`import AnchorCore` 는 하지 않는다 (모듈이 아니므로). 테스트 타깃만 `@testable import`
로 AnchorCore 를 쓴다.

## Xcode 프로젝트가 필요한 이유

SwiftPM 은 `.app` 번들을 만들지 못한다. 메뉴바 앱은 `NSApplication` + `NSPopover` 로
직접 떠야 하므로 (SwiftUI `App` Scene 는 `LSUIElement` 조합에서 불안정) Info.plist 와
번들 설정이 있는 Xcode 프로젝트가 반드시 필요하다.

`AnchorApp.xcodeproj` 는 `Scripts/gen_xcodeproj.py` 가 생성한다. 소스 파일이
추가되거나 이름이 바뀌면 스크립트를 다시 돌린다.

```bash
python3 Scripts/gen_xcodeproj.py
```

pbxproj 를 손으로 쓰지 않는 이유는, 이 프로젝트가 GitHub Actions 에서
`swift build` 만 돌리면 앱을 빌드할 수 없기 때문이다. 앱 빌드는 로컬 전용이다.

## 검증 모드

```bash
# 창을 띄워서 레이아웃 확인 (메뉴바 대신 일반 창)
ANCHOR_UI_TEST=1 Anchor.app/Contents/MacOS/Anchor

# 저장 경로만 검증하고 종료 (창 조작 없이 AppModel.saveDraft 실행)
cd ~/projects/개인/SaaS·앱/anchor
ANCHOR_SELFTEST=1 ANCHOR_SELFTEST_DB=/tmp/t.db \
  Anchor.app/Contents/MacOS/Anchor
```

`ANCHOR_SELFTEST` 는 폼을 채운 뒤 저장하고 DB 에 들어갔는지 확인한다.
CLI 로 같은 DB 를 열어 교차 검증할 수 있습니다.

```bash
anchor --db /tmp/t.db show 1
```

## 주의

- 앱을 다른 저장소에서 기록하려면 **그 저장소 디렉터리에서 실행**해야 프로젝트가
  제대로 잡힙니다. Dock 에서 실행하면 마지막 프로젝트로 기록됩니다.
- `testPanel` 은 반드시 strong reference 로 유지해야 합니다. 지역변수로 두면 ARC 가
  dealloc 하면서 AppKit 애니메이션 중 over-release 크래시가 납니다.
