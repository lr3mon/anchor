#!/usr/bin/env python3
"""anchor .app 번들 빌드.

SwiftPM 은 .app 번들을 만들지 못한다. RunFox 도 같은 이유로 이 방식을 쓴다:
SwiftPM 으로 바이너리를 만들고, 번들 디렉터리(Contents/MacOS, Info.plist,
.icns)를 직접 조립한 뒤 ad-hoc 서명한다.

사용법:
    python3 Scripts/package.py                 # 빌드 + dist/Anchor.app + zip
    python3 Scripts/package.py --install       # ~/Applications 에 설치
    python3 Scripts/package.py --version 0.2.0
"""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
APP = DIST / "Anchor.app"
BUNDLE_ID = "com.stpdfx.anchor"
DEFAULT_VERSION = "0.2.0"


def run(*args, **kwargs):
    print("+", " ".join(str(a) for a in args), flush=True)
    subprocess.run([str(a) for a in args], check=True, cwd=ROOT, **kwargs)


def build_binaries():
    """앱과 CLI 를 release 로 빌드한다."""
    run(sys.executable, ROOT / "Scripts/make_assets.py")
    run("swift", "build", "-c", "release", "--product", "AnchorApp")
    run("swift", "build", "-c", "release", "--product", "anchor")
    return Path(
        subprocess.check_output(
            ["swift", "build", "-c", "release", "--show-bin-path"],
            cwd=ROOT, text=True,
        ).strip()
    )


def assemble(bin_path: Path, version: str):
    if APP.exists():
        shutil.rmtree(APP)
    (APP / "Contents/MacOS").mkdir(parents=True)
    (APP / "Contents/Resources/bin").mkdir(parents=True)

    # 앱 바이너리: 번들 이름(Anchor)과 다르면 macOS 가 실행을 거부한다.
    shutil.copy2(bin_path / "AnchorApp", APP / "Contents/MacOS/Anchor")
    # CLI 를 앱 안 Resources/bin 에 넣는다. 앱이 밖의 PATH 에 기대지 않게.
    shutil.copy2(bin_path / "anchor", APP / "Contents/Resources/bin/anchor")
    os.chmod(APP / "Contents/MacOS/Anchor", 0o755)
    os.chmod(APP / "Contents/Resources/bin/anchor", 0o755)

    icns = ROOT / "Assets/Anchor.icns"
    if not icns.exists():
        run("iconutil", "-c", "icns", ROOT / "Assets/Anchor.iconset", "-o", icns)
    shutil.copy2(icns, APP / "Contents/Resources/Anchor.icns")

    info = {
        "CFBundleDevelopmentRegion": "ko",
        "CFBundleDisplayName": "anchor",
        "CFBundleExecutable": "Anchor",
        "CFBundleIconFile": "Anchor",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Anchor",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version.replace(".", ""),
        "LSMinimumSystemVersion": "14.0",
        # 메뉴바 앱: Dock 에 안 뜨고 메뉴바 아이콘만 남긴다.
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "© 2026 stpd_fx",
    }
    with open(APP / "Contents/Info.plist", "wb") as f:
        plistlib.dump(info, f, sort_keys=True)

    run("plutil", "-lint", APP / "Contents/Info.plist")
    # ad-hoc 서명. Apple Developer 계정 없이도 Gatekeeper 로컬 실행이 가능하다.
    run("codesign", "--force", "--deep", "--sign", "-", APP)
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", APP)
    return APP


def make_zip(version: str) -> Path:
    z = DIST / f"Anchor-{version}-macOS-arm64.zip"
    if z.exists():
        z.unlink()
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, z)
    return z


def install_app():
    dest = Path.home() / "Applications" / "Anchor.app"
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(APP, dest)
    # 설치본 재서명 (복사하면서 서명이 날릴 수 있다)
    run("codesign", "--force", "--deep", "--sign", "-", dest)
    print(f"INSTALL={dest}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default=DEFAULT_VERSION)
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--skip-build", action="store_true",
                    help="이미 빌드돼 있다면 건너뛴다 (빠른 재조립)")
    args = ap.parse_args()

    if args.skip_build:
        bin_path = Path(
            subprocess.check_output(
                ["swift", "build", "-c", "release", "--show-bin-path"],
                cwd=ROOT, text=True,
            ).strip()
        )
    else:
        bin_path = build_binaries()

    app = assemble(bin_path, args.version)
    z = make_zip(args.version)
    if args.install:
        install_app()
    print(f"APP={app}")
    print(f"ZIP={z}")


if __name__ == "__main__":
    main()
