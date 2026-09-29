import AppKit

// 메뉴바 앱은 SwiftUI App Scene (@main) 대신 NSApplication 을 직접 돌린다.
// LSUIElement=true 인 상태에서 SwiftUI Scene 은 씬이 안 뜬 버그가 있고,
// 메뉴바 앱은 씬 자체가 필요 없다. RunFox 도 같은 이유로 이 방식을 쓴다.
//
// 실행 방식:
//   swift build -c release --product AnchorApp
//   .build/release/AnchorApp
// 배포용 .app 번들은 Scripts/package.py 가 이 바이너리를 조립한다.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
