# 릴리스 체크리스트

버전 올릴 때 따라가면 됩니다.

## 1. 테스트 통과 확인

```bash
swift test
```

## 2. 버전 bump

`homebrew/anchor.rb` 의 `version` 과 `url` 의 `v#{version}` 을 함께 고칩니다.

```ruby
version "0.2.0"
url ".../releases/download/v0.2.0/anchor-macos-arm64.tar.gz"
```

## 3. 로컬에서 tar.gz + sha256 산출

Homebrew 는 sha256 이 틀리면 설치를 거부하므로 순서가 중요합니다.

```bash
swift build -c release --arch arm64
cd .build/arm64-apple-macosx/release
tar -czf anchor-macos-arm64.tar.gz anchor
shasum -a 256 anchor-macos-arm64.tar.gz | cut -d' ' -f1
```

## 4. 커밋 + 태그

```bash
git add -A
git commit -m "chore: v0.2.0"
git tag v0.2.0
git push origin main --tags
```

## 5. 릴리스 생성

```bash
gh release create v0.2.0 \
  .build/arm64-apple-macosx/release/anchor-macos-arm64.tar.gz \
  --title "v0.2.0" --generate-notes
```

## 6. sha256 을 formula 에 반영 후 tap 갱신

**릴리스에 올린 tar.gz 와 sha256 이 정확히 일치해야 합니다.** tar.gz 를 다시 만들면
sha256 이 바뀌므로, 3번에서 만든 파일을 그대로 5번에 올렸는지 확인합니다.

```bash
SHA=$(shasum -a 256 .build/arm64-apple-macosx/release/anchor-macos-arm64.tar.gz | cut -d' ' -f1)
# homebrew/anchor.rb 의 sha256 을 $SHA 로 교체
```

tap 저장소 경로는 `~/Library/Caches` 가 아니라 직접 clone 한 곳을 씁니다.

```bash
cd /tmp/anchor-tap        # clone 해둔 tap 저장소
cp ~/projects/개인/SaaS·앱/anchor/homebrew/anchor.rb Formula/
git add -A && git commit -m "anchor v0.2.0" && git push
```

## 7. 설치 검증

로컬에서 진짜 설치가 되는지 반드시 확인합니다.

```bash
brew update && brew upgrade anchor
brew test anchor
anchor --help
```

## 주의

- **저장소 이름이 `tap` 이 아니라 `homebrew-tap` 이어야 합니다.** Homebrew 가
  `lr3mon/tap` → `lr3mon/homebrew-tap` 로 자동 변환하기 때문입니다.
- `~/.local/bin/anchor` 같은 수동 설치본이 남아 있으면 brew 버전을 가립니다.
  `which -a anchor` 로 확인하고 정리합니다.
- arm64 전용입니다. Intel 지원이 필요하면 universal 빌드로 바꿔야 합니다
  (`swift build -c release --arch arm64 --arch x86_64`).
