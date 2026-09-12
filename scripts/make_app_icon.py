#!/usr/bin/env python3
"""Generate the macOS app icon set.

Kept as a script rather than ten checked-in binaries someone has to redraw by
hand: the mark is drawn from the same visual language as the plan canvas — a
parchment plot, crop rows, a pitched-roof symbol — so changing the palette
means editing three constants here, not reopening a drawing tool.

    python3 scripts/make_app_icon.py

Writes every size macOS asks for into the AppIcon.appiconset alongside its
existing Contents.json.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Homestead/Homestead/Assets.xcassets/AppIcon.appiconset"

# Straight from the web app's CATEGORY_STYLES, so the icon, the canvas and the
# legend all read as the same product.
GROUND = (47, 79, 58)        # deep field green
GROUND_EDGE = (36, 61, 45)
PARCHMENT = (236, 228, 206)  # residential fill, warmed
ROOF = (58, 53, 39)
CROP = (95, 125, 58)         # food-annual stroke
CANVAS = 1024


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_icon() -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # Ground: a vertical gradient so the tile doesn't read as flat colour.
    for y in range(CANVAS):
        t = y / (CANVAS - 1)
        colour = tuple(round(GROUND[i] + (GROUND_EDGE[i] - GROUND[i]) * t) for i in range(3))
        draw.line([(0, y), (CANVAS, y)], fill=colour + (255,))

    # The plot: a parchment field inset from the tile edge.
    margin = CANVAS * 0.17
    plot = [margin, margin, CANVAS - margin, CANVAS - margin]
    draw.rounded_rectangle(plot, radius=int(CANVAS * 0.045), fill=PARCHMENT + (255,))

    # Crop rows across the upper third — the "planned land" half of the mark.
    # A solid dark block with hip lines reads as an envelope at icon size, so
    # the building is a gable silhouette instead: unmistakably a house.
    row_left = margin + CANVAS * 0.06
    row_right = CANVAS - margin - CANVAS * 0.06
    for i in range(3):
        y = margin + CANVAS * 0.085 + i * CANVAS * 0.062
        draw.line([(row_left, y), (row_right, y)], fill=CROP + (200,), width=int(CANVAS * 0.019))

    # House: a gable end — walls plus a pitched roof, the one silhouette that
    # still says "house" at 16 pixels.
    cx = CANVAS * 0.44
    eaves = CANVAS * 0.60
    base = CANVAS - margin - CANVAS * 0.085
    half = CANVAS * 0.135
    ridge = CANVAS * 0.495
    draw.polygon(
        [(cx - half, eaves), (cx, ridge), (cx + half, eaves), (cx + half, base), (cx - half, base)],
        fill=ROOF + (255,),
    )
    # Door, so the mass isn't a featureless blob at larger sizes.
    door_half = half * 0.24
    draw.rectangle(
        [cx - door_half, base - (base - eaves) * 0.62, cx + door_half, base],
        fill=PARCHMENT + (235,),
    )

    # A tree beside it: canopy plus trunk, matching the orchard glyph.
    tree_x = CANVAS * 0.72
    canopy_r = CANVAS * 0.072
    canopy_y = base - CANVAS * 0.105
    draw.ellipse(
        [tree_x - canopy_r, canopy_y - canopy_r, tree_x + canopy_r, canopy_y + canopy_r],
        fill=CROP + (255,),
    )
    trunk_half = CANVAS * 0.012
    draw.rectangle([tree_x - trunk_half, canopy_y, tree_x + trunk_half, base], fill=ROOF + (255,))

    image.putalpha(rounded_mask(CANVAS, int(CANVAS * 0.22)))
    return image


def main() -> None:
    icon = draw_icon()
    contents = json.loads((ICONSET / "Contents.json").read_text())

    for entry in contents["images"]:
        points = int(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        pixels = points * scale
        name = f"icon_{points}x{points}@{scale}x.png"
        icon.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name)
        entry["filename"] = name

    (ICONSET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"wrote {len(contents['images'])} images to {ICONSET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
