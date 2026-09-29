#!/usr/bin/env python3
"""anchor 앱 아이콘 생성기.

앱 아이콘이 없으면 Finder/Dock 에서 generic 아이콘으로 보인다. 메뉴바 앱이라
Dock 에는 안 뜨지만, 설치 폴더와 Spotlight 에서 아이콘이 보이므로 만든다.
16비트 픽셀 아트 느낌을 살려 anchor(닻) 모양을 손으로 그린다.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
ASSETS.mkdir(parents=True, exist_ok=True)

# 메뉴바에서 쓰는 template 이미지용 단색 (알파만 남긴다).
TEMPLATE = (0, 0, 0, 255)


GRID_W, GRID_H = 12, 14


def anchor_sprite(unit: int = 8) -> Image.Image:
    """닻 모양 스프라이트. GRID_W x GRID_H 격자, y=0 이 맨 위."""
    img = Image.new("RGBA", (GRID_W * unit, GRID_H * unit), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def px(x, y):
        d.rectangle(
            (x * unit, y * unit, (x + 1) * unit - 1, (y + 1) * unit - 1),
            fill=TEMPLATE,
        )

    # 위쪽 링 (속이 빈 사각형)
    for x, y in [(5, 0), (6, 0), (4, 1), (7, 1), (4, 2), (7, 2), (5, 3), (6, 3)]:
        px(x, y)

    # 세로 축 (링 아래부터 바닥까지)
    for y in range(4, GRID_H):
        px(5, y)
        px(6, y)

    # 가로 빔 (crossbar)
    for x in range(1, 11):
        px(x, 5)

    # 양쪽 팔: 빔 끝에서 아래로 내려갔다가 끝으로 올라온다 (닻의 갈고리)
    arms = {
        6:  (1, 10),
        7:  (0, 11),
        8:  (0, 11),
        9:  (1, 10),
        10: (1, 10),
        11: (2, 9),
        12: (2, 9),
        13: (1, 10),   # 끝이 위로 튀어 오른다
    }
    for y, (xl, xr) in arms.items():
        px(xl, y)
        px(xr, y)
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def make_icon():
    size = 1024
    tile = Image.new("RGBA", (size, size))
    pix = tile.load()
    # 세로 그라데이션 배경 (남색 → 짙은 청록)
    for y in range(size):
        t = y / (size - 1)
        r = int(22 * (1 - t) + 12 * t)
        g = int(34 * (1 - t) + 26 * t)
        b = int(58 * (1 - t) + 46 * t)
        for x in range(size):
            pix[x, y] = (r, g, b, 255)
    tile.putalpha(rounded_mask(size, 220))

    # 닻 스프라이트를 타일 안쪽(여백 18%)에 맞춰 확대 배치
    margin = int(size * 0.18)
    box = size - margin * 2
    sprite = anchor_sprite(unit=8)
    # NEAREST 로 확대해 픽셀 아트 느낌을 유지한다 (Lanczos 는 뭉개진다)
    target_w = box
    scale = target_w / sprite.width
    sprite = sprite.resize(
        (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
        Image.Resampling.NEAREST,
    )
    # 흰색으로 칠하기 (알파 마스크만 사용)
    white = Image.new("RGBA", sprite.size, (240, 246, 252, 255))
    white.putalpha(sprite.getchannel("A"))
    tile.alpha_composite(white, ((size - white.width) // 2, (size - white.height) // 2))

    # 하단에 픽셀 스파크 (속도감 있는 느낌)
    d = ImageDraw.Draw(tile)
    for x, y, s in [(300, 780, 26), (250, 850, 18), (356, 846, 14)]:
        d.rectangle((x, y, x + s, y + s), fill=(240, 246, 252, 255))

    icon_path = ASSETS / "AnchorIcon.png"
    tile.save(icon_path)

    # iconset 생성 (iconutil 이 요구하는 사이즈들)
    iconset = ASSETS / "Anchor.iconset"
    iconset.mkdir(exist_ok=True)
    for size_px in [16, 32, 64, 128, 256, 512, 1024]:
        for scale in [1, 2]:
            dim = size_px * scale
            if dim > 1024:
                continue
            resized = tile.resize((dim, dim), Image.Resampling.LANCZOS)
            name = f"icon_{size_px}x{size_px}.png" if scale == 1 else f"icon_{size_px}x{size_px}@2x.png"
            resized.save(iconset / name)
    print(f"ICONSET={iconset}")
    print(f"ICON={icon_path}")


def make_template_iconset():
    """메뉴바 상태아이콘용 template PNG 시트.

    단색(검정) 닻 + 활성 상태(기록 있음) 강조. macOS 가 template 으로 물들이므로
    알파만 있으면 라이트/다크 메뉴바 모두에 맞는다.
    """
    iconset = ASSETS / "AnchorMenuBar.iconset"
    iconset.mkdir(exist_ok=True)
    sprite = anchor_sprite(unit=8)
    # 2프레임: 기본 / 활성(기록이 있을 때 살짝 두꺼운 느낌은 생략하고
    # 앵커가 살짝 떠 있는 느낌)
    for size_px in [16, 32, 64, 128, 256, 512, 1024]:
        for scale in [1, 2]:
            dim = size_px * scale
            if dim > 1024:
                continue
            r = sprite.resize((int(14 * 1.5 * 32), int(16 * 1.5 * 32)), Image.Resampling.NEAREST)
            r = r.resize((dim, dim), Image.Resampling.LANCZOS)
            name = f"icon_{size_px}x{size_px}.png" if scale == 1 else f"icon_{size_px}x{size_px}@2x.png"
            r.save(iconset / name)
    print(f"MENUBAR_ICONSET={iconset}")


if __name__ == "__main__":
    make_icon()
    make_template_iconset()
