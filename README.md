# anchor

결정 기록 + 회고 CLI. 왜 이렇게 정했는지 남겨두면 나중에 "이거 왜 이래?"가 안 생깁니다.

macOS 전용. 외부 의존성 없음(system `libsqlite3` 사용), 설치하면 정적 바이너리 하나만 있으면 됩니다.

## 설치

```bash
# Homebrew (권장)
brew install lr3mon/tap/anchor

# 또는 직접
curl -fsSL https://raw.githubusercontent.com/lr3mon/tap/main/install.sh | bash
anchor --help
```

## 쓰기

```bash
# 지금 있는 git 저장소를 자동으로 인식해서 기록
cd ~/projects/개인/SaaS·앱/some-project
anchor new "결정 로그를 SQLite로 옮김" \
  --context "JSON 파일이 병합이 안 돼서 충돌남" \
  --choice "system libsqlite3 직접 사용" \
  --alt "GRDB::의존성 추가 / 이득 없음" \
  --alt "PostgreSQL::로컬 도구엔 과함" \
  --tags "sqlite,decision-log"

anchor ls                     # 목록
anchor show 1                 # 상세 (상황/결정/기각한 대안)
anchor retro 7                # 최근 7일 회고
```

## 핵심 개념

도구는 네 가지만 저장합니다.

- **상황** — 무슨 일이 있어서 결정을 내려야 했나
- **결정** — 무엇으로 정했나
- **기각한 대안** — 왜 안 했나 (가장 중요함)
- **상태** — `proposed` / `accepted` / `superseded` / `rejected`

"기각한 대안"이 이 도구가 다른 할 일 목록과 다른 점입니다. 나중에 같은 문제를 다시 만나면
왜 그때는 이걸 고르지 않았는지가 남아 있어야 같은 실수를 반복하지 않습니다.

## 명령

| 명령 | 하는 일 |
|---|---|
| `anchor new "제목"` | 결정 기록 (cwd 의 git 저장소 자동 감지) |
| `anchor ls [--all]` | 목록. `--status` `--tag` `--search` 필터 |
| `anchor show <id>` | 상세 |
| `anchor edit <id> "제목"` | 수정 |
| `anchor set <id> --status accepted` | 상태 변경 |
| `anchor alt <id> "옵션::이유"` | 대안 추가 |
| `anchor rm <id> --yes` | 삭제 (확인 없이 못 지운다) |
| `anchor retro [일수]` | 기간별 회고 + 자주 나온 주제 |
| `anchor note "제목" --summary "..."` | 회고 노트 |
| `anchor projects` | 프로젝트별 요약 |
| `anchor tags` | 태그 목록 |
| `anchor export [--json]` | 마크다운 / JSON 내보내기 |

## 데이터 위치

```
~/.anchor/decisions.db
```

SQLite 파일 하나입니다. 백업하려면 그 파일만 복사하면 됩니다.

## 개발

```bash
swift build              # 디버그 빌드
swift test               # 테스트 (12개)
swift build -c release --arch arm64
```

구조는 `Sources/AnchorCore`(로직, 테스트 가능) + `Sources/Anchor`(진입점) 두 타깃으로
나눴습니다. `executableTarget` 은 `@testable import` 가 되지 않아 테스트를 붙일 수
없으므로, 같은 소스를 쓰는 library 타깃을 두는 구조입니다.

## 요구사항

- macOS 14+
- Swift 6.x (개발용)
