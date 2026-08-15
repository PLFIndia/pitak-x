#!/usr/bin/env python3
"""Generate Google Play listing graphics from the Pitak brand mark.

Play requires a 1024x500 feature graphic (shown at the top of the listing).
The design is deliberately minimal and brand-consistent: saffron field, the
open-book mark, and the "Pitak" wordmark in cream Noto Sans Bold (the bundled
OFL font, so no system-font dependency).

The 512x512 hi-res icon is handled by gen_app_icon.py (single source of truth
for the mark); this script imports its render() so the two never drift.

Run from the repo root:  python3 tool/gen_play_assets.py
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_app_icon import BG, PAGE, REPO, render  # noqa: E402

FEATURE_GRAPHIC = "fastlane/metadata/android/en-US/images/featureGraphic.png"
WORDMARK_FONT = "assets/fonts/NotoSans-Bold.ttf"

W, H = 1024, 500
TILE = 360          # book mark size
GAP = 48            # space between mark and wordmark
FONT_PX = 150


def main() -> None:
    img = Image.new("RGB", (W, H), BG)
    tile = render(TILE)

    font = ImageFont.truetype(os.path.join(REPO, WORDMARK_FONT), FONT_PX)
    probe = ImageDraw.Draw(img)
    # Center the (tile + gap + text) group as one unit, optically: the text
    # bounding box (not the em box) is what the eye centres on.
    tb = probe.textbbox((0, 0), "Pitak", font=font)
    text_w, text_h = tb[2] - tb[0], tb[3] - tb[1]
    total = TILE + GAP + text_w
    x = (W - total) // 2
    img.paste(tile, (x, (H - TILE) // 2))
    probe.text(
        (x + TILE + GAP - tb[0], (H - text_h) // 2 - tb[1]),
        "Pitak",
        font=font,
        fill=PAGE,
    )

    out = os.path.join(REPO, FEATURE_GRAPHIC)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, "PNG")
    print(f"wrote {FEATURE_GRAPHIC} ({W}x{H})")


if __name__ == "__main__":
    main()
