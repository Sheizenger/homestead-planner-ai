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
SKY = (198, 222, 226)        # greenhouse fill, lightened
SKY_LOW = (168, 201, 190)
GROUND = (92, 140, 74)       # field green
GROUND_EDGE = (57, 94, 52)
PARCHMENT = (236, 228, 206)  # residential fill, warmed
WALL_SHADE = (138, 122, 88)  # residential stroke
ROOF = (196, 85, 63)         # the red roof every reference leads with
CROP = (63, 107, 58)         # food-perennial stroke
FENCE = (222, 210, 179)
CANVAS = 1024


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_icon() -> Image.Image:
    """A cottage on a field behind a fence: the smallest scene that says
    "homestead" rather than "document" or "map" at 32 pixels."""
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    horizon = CANVAS * 0.56

    # Sky, warm to cool so the roof reads against it.
    for y in range(int(horizon)):
        t = y / max(1, horizon - 1)
        colour = tuple(round(SKY[i] + (SKY_LOW[i] - SKY[i]) * t) for i in range(3))
        draw.line([(0, y), (CANVAS, y)], fill=colour + (255,))

    # Field, darker toward the front edge.
    for y in range(int(horizon), CANVAS):
        t = (y - horizon) / max(1, CANVAS - horizon - 1)
        colour = tuple(round(GROUND[i] + (GROUND_EDGE[i] - GROUND[i]) * t) for i in range(3))
        draw.line([(0, y), (CANVAS, y)], fill=colour + (255,))

    # Crop rows, converging slightly so the field reads as ground rather than
    # a flat band of colour.
    for i in range(4):
        t = (i + 1) / 5
        y = horizon + (CANVAS - horizon) * (t ** 1.5) * 0.82
        inset = CANVAS * 0.10 * (1 - t)
        draw.line(
            [(inset, y), (CANVAS - inset, y)],
            fill=CROP + (150,),
            width=max(2, int(CANVAS * 0.012 * (0.6 + t))),
        )

    # House: walls, pitched roof, chimney, door, window.
    cx = CANVAS * 0.42
    base = CANVAS * 0.70
    eaves = CANVAS * 0.42
    ridge = CANVAS * 0.26
    half = CANVAS * 0.165

    draw.rectangle([cx - half * 0.86, eaves, cx + half * 0.86, base], fill=PARCHMENT + (255,))
    # Chimney first, so the roof overlaps its base.
    chim_x = cx + half * 0.42
    draw.rectangle([chim_x, ridge - CANVAS * 0.075, chim_x + CANVAS * 0.036, eaves], fill=WALL_SHADE + (255,))
    draw.polygon([(cx - half, eaves), (cx, ridge), (cx + half, eaves)], fill=ROOF + (255,))

    door_w = CANVAS * 0.036
    draw.rectangle([cx - door_w, base - CANVAS * 0.105, cx + door_w, base], fill=WALL_SHADE + (255,))
    win = CANVAS * 0.030
    win_y = eaves + CANVAS * 0.045
    draw.rectangle([cx + half * 0.30, win_y, cx + half * 0.30 + win * 2, win_y + win * 2], fill=SKY + (255,))

    # Tree to the right of the house.
    tree_x = CANVAS * 0.735
    canopy_r = CANVAS * 0.085
    canopy_y = CANVAS * 0.50
    draw.ellipse(
        [tree_x - canopy_r, canopy_y - canopy_r, tree_x + canopy_r, canopy_y + canopy_r],
        fill=CROP + (255,),
    )
    draw.rectangle(
        [tree_x - CANVAS * 0.013, canopy_y, tree_x + CANVAS * 0.013, CANVAS * 0.70],
        fill=WALL_SHADE + (255,),
    )

    # Fence across the foreground: two rails on posts, the element that says
    # "a holding" rather than "a landscape".
    fence_y = CANVAS * 0.80
    post_h = CANVAS * 0.135
    rail_w = max(3, int(CANVAS * 0.020))
    for rail in (0.30, 0.66):
        y = fence_y + post_h * rail
        draw.line([(CANVAS * 0.06, y), (CANVAS * 0.94, y)], fill=FENCE + (255,), width=rail_w)
    for i in range(6):
        x = CANVAS * 0.10 + i * CANVAS * 0.16
        draw.rectangle([x - rail_w * 0.8, fence_y, x + rail_w * 0.8, fence_y + post_h], fill=FENCE + (255,))

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
