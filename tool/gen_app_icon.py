#!/usr/bin/env python3
"""Generate the Pitak app icon for every platform from one vector source.

Single source of truth for the launcher icon. The Pitak mark is a saffron tile
with a cream book lying open face-up, defined in a 108-unit viewport (the
Android adaptive-icon convention). Adapted from the F-Droid listing-icon
script in the Pitak_fdroid repo; GLYPH_SCALE enlarges the book around the tile
centre so it fills the icon instead of floating in a wide saffron margin.

Rendering is supersampled 8x then downscaled with LANCZOS for crisp edges.
The flat PNGs are opaque RGB (no alpha / no rounded corners): iOS and macOS
apply their own masks, and a full-bleed background avoids the App Store alpha
rejection.

Android 8+ also gets an ADAPTIVE icon (two layers: a saffron colour behind a
transparent book picture). Why (beginner note): those Android versions cut
every launcher icon to the phone's own shape (a circle on most phones). An app
that ships only a flat square picture gets it shrunk onto a WHITE plate, so
the user sees a saffron square inside a white circle. With two layers the
launcher fills its whole shape with the saffron background instead. The
adaptive book is smaller (ADAPTIVE_GLYPH_SCALE) because the shape cuts off the
tile's edges.

Run from the repo root:  python3 tool/gen_app_icon.py
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw

VIEWPORT = 108          # adaptive-icon vector viewport
SS = 8                  # supersampling factor
CENTER = 54.0           # tile centre, glyph is scaled around this point
GLYPH_SCALE = 1.78      # flat icons: book ~64% of the tile width (was ~33%)
# Adaptive icon: a launcher shows only the middle 72 of the 108 units, cut to
# its own shape, and promises to keep only the middle circle of diameter 66
# (the "safe zone") on every shape. At 1.10 the book is ~60% of the visible
# circle wide and its farthest corner sits ~29.6 units from the centre, inside
# the 33-unit safe radius, so no launcher shape clips it. Chosen by the product
# owner on 2026-11-03 after rendered previews of 1.05, 1.15 and 1.25.
ADAPTIVE_GLYPH_SCALE = 1.10

BG = (0xE2, 0x58, 0x22)           # pitaka_saffron_400
PAGE = (0xFF, 0xFA, 0xF5)         # cream paper (pages and cover edge)
FOLD_SHADOW = (0xE2, 0xC4, 0xA8)  # warm tan: the shadow ON the paper by the fold
FOLD_LINE = (0xC4, 0x96, 0x74)    # the crease itself

# ---------------------------------------------------------------------------
# The book, in 108-viewport units. Only the LEFT half is described; the right
# half is its mirror image. Image y grows DOWNWARD (bigger y = lower).
#
# Why it is drawn this way: a book lying open face-up sags into its centre
# fold, the paper is shaded where it bends into that fold, and its cover
# shows underneath the pages. Each of those three cues says "face-up"; an
# icon with none of them is ambiguous and the eye may read it as a book left
# open face-down. (Until 2026-10 the pages rose to a peak at a saffron spine
# band, which read exactly that way.) So:
#   1. the page edges stay level near the outer edge and curve DOWN into the
#      fold (the fold is the lowest point);
#   2. the paper darkens toward the fold, with a thin crease line on it;
#   3. a cream cover edge peeks out below the pages, slightly wider.
# The whole glyph spans x 34.5..73.5 and y 34..74, centred on the tile.
# ---------------------------------------------------------------------------
OUTER_X = 36.0           # outer edge of the left page
FOLD_X = 54.0            # the centre fold (= tile centre)
TOP_OUTER_Y = 34.0       # top edge: height at the outer edge...
TOP_FOLD_Y = 38.0        # ...and at the fold (4 units lower)
BOTTOM_OUTER_Y = 66.0    # bottom edge, same 4-unit sag
BOTTOM_FOLD_Y = 70.0
SAG_EXPONENT = 2.4       # >1 keeps the edge level, then bends late into the fold
COVER_OUTER_X = 34.5     # the cover sticks out 1.5 units past the pages
COVER_GAP = 1.5          # saffron gap between the pages and the cover edge
COVER_BOTTOM = 4.0       # the cover edge ends 4 units below the pages
SHADOW_REACH = 6.0       # the fold shadow fades out 6 units from the fold
FOLD_LINE_WIDTH = 0.7
EDGE_POINTS = 48         # straight segments used to approximate each curve

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Flat PNGs: relative path -> pixel size.
FLAT = {
    "assets/branding/app_icon.png": 192,
    "assets/pdf/app_icon.png": 192,
    # Google Play hi-res listing icon (fastlane supply path). Play requires
    # 512x512; this replaces the old 192px F-Droid listing icon at the same
    # path (F-Droid accepts 512 fine and downscales).
    "fastlane/metadata/android/en-US/images/icon.png": 512,
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

# Adaptive-icon FOREGROUND PNGs (the book on transparency): relative path ->
# pixel size. The layer is 108 dp, so its size is 108 x the density factor.
ADAPTIVE_FOREGROUND = {
    "android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png": 108,
    "android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png": 162,
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png": 216,
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png": 324,
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png": 432,
}

# The adaptive icon itself. `-v26` = Android 8.0+, the first version that
# understands adaptive icons; older phones keep using the flat ic_launcher.png
# (minSdk is 24). It has the same name as the flat icon, so the manifest's
# `@mipmap/ic_launcher` picks the right one on every phone.
ADAPTIVE_ICON_XML = "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
ADAPTIVE_ICON_XML_TEXT = """\
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/gen_app_icon.py. Do not edit by hand: change the script
     and run it again. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""

# The background layer's colour, written from BG so the saffron is defined in
# ONE place (this script). A file of its own, so the script owns all of it.
BACKGROUND_COLOR_XML = "android/app/src/main/res/values/ic_launcher_background.xml"


Point = tuple[float, float]


def _sag(x: float) -> float:
    """How far (0..1) an edge has dropped toward the fold at viewport x.

    0 at the outer page edge (and anywhere further out), 1 at the fold. The
    exponent keeps the paper nearly level at first, then bends it late, the
    way a page curves down into the gutter.
    """
    t = max(0.0, (x - OUTER_X) / (FOLD_X - OUTER_X))
    return t**SAG_EXPONENT


def _edge(start_x: float, y_outer: float, y_fold: float, offset: float = 0.0) -> list[Point]:
    """Points along one sagging edge, from start_x to the fold, moved down by offset."""
    points = []
    for i in range(EDGE_POINTS + 1):
        x = start_x + (FOLD_X - start_x) * i / EDGE_POINTS
        points.append((x, y_outer + (y_fold - y_outer) * _sag(x) + offset))
    return points


def _mirror(points: list[Point]) -> list[Point]:
    """The right half of the book: the left half flipped around the fold."""
    return [(2 * FOLD_X - x, y) for x, y in points]


def _left_page() -> list[Point]:
    top = _edge(OUTER_X, TOP_OUTER_Y, TOP_FOLD_Y)
    bottom = _edge(OUTER_X, BOTTOM_OUTER_Y, BOTTOM_FOLD_Y)
    return top + bottom[::-1]  # walk the top edge out, the bottom edge back


def _left_cover_edge() -> list[Point]:
    """The strip of cover visible below the left page, following its curve."""
    upper = _edge(COVER_OUTER_X, BOTTOM_OUTER_Y, BOTTOM_FOLD_Y, offset=COVER_GAP)
    lower = _edge(COVER_OUTER_X, BOTTOM_OUTER_Y, BOTTOM_FOLD_Y, offset=COVER_BOTTOM)
    return upper + lower[::-1]


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, ...]:
    """Colour a fraction t of the way from a to b."""
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(
    px: int,
    glyph_scale: float = GLYPH_SCALE,
    background: tuple[int, int, int] | None = BG,
) -> Image.Image:
    """The mark as a px x px image.

    By default: the flat icon (opaque RGB, saffron tile). With
    background=None: the book alone on a transparent RGBA canvas, which is the
    adaptive icon's foreground layer (the launcher supplies the saffron).
    """
    size = px * SS
    unit = size / VIEWPORT
    transparent = background is None
    mode = "RGBA" if transparent else "RGB"

    def ink(colour: tuple[int, ...]) -> tuple[int, ...]:
        # An RGBA canvas needs a 4th value (alpha): 255 = fully opaque.
        return (*colour, 255) if transparent else colour

    def to_pixels(points: list[Point]) -> list[Point]:
        # Scale the glyph by glyph_scale around the tile centre, then to pixels.
        return [
            (
                (CENTER + (x - CENTER) * glyph_scale) * unit,
                (CENTER + (y - CENTER) * glyph_scale) * unit,
            )
            for x, y in points
        ]

    img = Image.new(mode, (size, size), (0, 0, 0, 0) if transparent else background)
    draw = ImageDraw.Draw(img)

    # 1. The cover edge under the pages, then the pages themselves, flat cream.
    cover = _left_cover_edge()
    page = _left_page()
    for shape in (cover, _mirror(cover), page, _mirror(page)):
        draw.polygon(to_pixels(shape), fill=ink(PAGE))

    # 2. The fold shadow and crease, painted ONLY onto the pages. A mask of
    #    the page shapes works like a stencil: the shading strip shows through
    #    where the mask is white (the pages) and nowhere else.
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    for shape in (page, _mirror(page)):
        mask_draw.polygon(to_pixels(shape), fill=255)

    fold_x = FOLD_X * unit  # the fold is the tile centre, so scaling leaves it put
    reach = SHADOW_REACH * glyph_scale * unit
    left, right = int(fold_x - reach), int(fold_x + reach) + 1
    strip = Image.new(mode, (right - left + 1, size), ink(PAGE))
    strip_draw = ImageDraw.Draw(strip)
    for x in range(left, right + 1):
        # 0 at the fold -> 1 at the reach; the 0.7 power keeps the shadow
        # soft but concentrated near the crease.
        t = min(1.0, abs(x - fold_x) / reach)
        strip_draw.line(
            [(x - left, 0), (x - left, size)], fill=ink(_mix(FOLD_SHADOW, PAGE, t**0.7))
        )
    half_line = FOLD_LINE_WIDTH * glyph_scale * unit / 2
    strip_draw.rectangle(
        [fold_x - half_line - left, 0, fold_x + half_line - left, size], fill=ink(FOLD_LINE)
    )
    img.paste(strip, (left, 0), mask.crop((left, 0, right + 1, size)))

    if not transparent:
        return img.resize((px, px), Image.LANCZOS)
    # Shrink with "premultiplied" alpha (RGBa): each colour is weighted by its
    # opacity while pixels are averaged. Otherwise the invisible black of the
    # transparent area would bleed into the edge pixels as a dark fringe.
    return img.convert("RGBa").resize((px, px), Image.LANCZOS).convert("RGBA")


def _write_text(rel: str, text: str) -> None:
    out = os.path.join(REPO, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(f"wrote {rel}")


def main() -> None:
    cache: dict[int, Image.Image] = {}
    for rel, px in FLAT.items():
        if px not in cache:
            cache[px] = render(px)
        out = os.path.join(REPO, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        cache[px].save(out, "PNG")
        print(f"wrote {rel} ({px}x{px})")

    for rel, px in ADAPTIVE_FOREGROUND.items():
        out = os.path.join(REPO, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        render(px, glyph_scale=ADAPTIVE_GLYPH_SCALE, background=None).save(out, "PNG")
        print(f"wrote {rel} ({px}x{px}, transparent)")

    _write_text(ADAPTIVE_ICON_XML, ADAPTIVE_ICON_XML_TEXT)
    red, green, blue = BG
    _write_text(
        BACKGROUND_COLOR_XML,
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Generated by tool/gen_app_icon.py from BG (pitaka_saffron_400).\n"
        "     Do not edit by hand: change the script and run it again. -->\n"
        "<resources>\n"
        f'    <color name="ic_launcher_background">#{red:02X}{green:02X}{blue:02X}</color>\n'
        "</resources>\n",
    )


if __name__ == "__main__":
    main()
