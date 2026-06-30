#!/usr/bin/env python3
"""Generate the Pitak app icon for every platform from one vector source.

Single source of truth for the launcher icon. The Pitak mark is a saffron tile
with a cream open-book glyph, defined as flat polygons in a 108-unit viewport
(the Android adaptive-icon convention). Adapted from the F-Droid listing-icon
script in the Pitak_fdroid repo; the only change is GLYPH_SCALE, which enlarges
the book around the tile centre so it fills the icon instead of floating in a
wide saffron margin.

Rendering is supersampled 8x then downscaled with LANCZOS for crisp edges.
Output is opaque RGB (no alpha / no rounded corners): iOS and macOS apply their
own masks, and a full-bleed background avoids the App Store alpha rejection.

Run from the repo root:  python3 tool/gen_app_icon.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

VIEWPORT = 108          # adaptive-icon vector viewport
SS = 8                  # supersampling factor
CENTER = 54.0           # tile centre, glyph is scaled around this point
GLYPH_SCALE = 1.78      # book ~59% of the tile (was ~33%); safe for adaptive crop

BG = (0xE2, 0x58, 0x22)     # pitaka_saffron_400
PAGE = (0xFF, 0xFA, 0xF5)   # cream pages
SPINE = (0xC9, 0x4F, 0x1E)  # darker saffron spine

# Open-book polygons in 108-viewport coords (left page, right page, spine).
PATHS = [
    ([(36, 40), (36, 72), (52, 68), (52, 36)], PAGE),
    ([(72, 40), (72, 72), (56, 68), (56, 36)], PAGE),
    ([(52, 36), (52, 68), (56, 68), (56, 36)], SPINE),
]

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Flat PNGs: relative path -> pixel size.
FLAT = {
    "assets/branding/app_icon.png": 192,
    "assets/pdf/app_icon.png": 192,
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
    # iOS AppIcon set (filename -> px)
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": 20,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": 60,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": 29,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": 58,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": 87,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": 80,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": 180,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": 76,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": 152,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": 167,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": 1024,
    # macOS AppIcon set
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": 16,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": 32,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": 64,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": 128,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": 256,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": 512,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": 1024,
}


def render(px: int) -> Image.Image:
    size = px * SS
    scale = size / VIEWPORT
    img = Image.new("RGB", (size, size), BG)
    draw = ImageDraw.Draw(img)
    for pts, fill in PATHS:
        scaled = [
            (
                (CENTER + (x - CENTER) * GLYPH_SCALE) * scale,
                (CENTER + (y - CENTER) * GLYPH_SCALE) * scale,
            )
            for (x, y) in pts
        ]
        draw.polygon(scaled, fill=fill)
    return img.resize((px, px), Image.LANCZOS)


def main() -> None:
    cache: dict[int, Image.Image] = {}
    for rel, px in FLAT.items():
        if px not in cache:
            cache[px] = render(px)
        out = os.path.join(REPO, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        cache[px].save(out, "PNG")
        print(f"wrote {rel} ({px}x{px})")


if __name__ == "__main__":
    main()
