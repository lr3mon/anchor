#!/bin/bash
# anchor 설치 스크립트. macOS arm64 전용.
# Homebrew 없이 쓰려면: curl -fsSL .../install.sh | bash
set -euo pipefail

REPO="lr3mon/anchor"
BIN="anchor"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "anchor 는 macOS 전용입니다." >&2
  exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  echo "지원하지 않는 아키텍처입니다: $ARCH (Apple Silicon 만 지원)" >&2
  exit 1
fi

PREFIX="${PREFIX:-$HOME/.local/bin}"
TAG="${ANCHOR_VERSION:-latest}"

echo "→ anchor 설치 중 ($TAG, $ARCH)"

if [[ "$TAG" == "latest" ]]; then
  URL="https://github.com/$REPO/releases/latest/download/anchor-macos-arm64.tar.gz"
else
  URL="https://github.com/$REPO/releases/download/$TAG/anchor-macos-arm64.tar.gz"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$URL" -o "$TMP/anchor.tar.gz"
tar -xzf "$TMP/anchor.tar.gz" -C "$TMP"

mkdir -p "$PREFIX"
install -m 0755 "$TMP/$BIN" "$PREFIX/$BIN"

echo "✓ 설치 완료: $PREFIX/$BIN"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *)
    echo
    echo "⚠ PATH 에 $PREFIX 가 없습니다. 추가하려면:"
    echo "  echo 'export PATH=\"$PREFIX:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

echo
"$PREFIX/$BIN" --help | head -5
