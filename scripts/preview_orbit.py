#!/usr/bin/env python3
"""Draw the massing from several camera angles, so rotation can be *seen*.

`preview_massing.py` proved its worth by finding two faults that three
rounds of reading the code had missed, but it has the old fixed projection
and the old `x + y` depth sort written into it — the very things `Camera3D`
generalises. It therefore cannot say anything about whether the view still
holds together once the camera moves, which is the whole question.

This is the same transcription with the camera as a parameter. It renders a
contact sheet across a turn and at both ends of the pitch clamp, and it also
asserts the two properties that are cheap to check numerically and expensive
to spot by eye:

  - every face drawn as visible really does face the camera, and a closed box
    never shows more than half its walls;
  - nothing is painted over something strictly nearer to the camera.

Usage:

    python3 scripts/preview_orbit.py && open orbit.png
"""

import math
import sys

# --- Camera3D, transcribed -------------------------------------------------

UNIT = math.sqrt(2) * math.cos(math.pi / 6)
ISO_YAW = -math.pi / 4
ISO_PITCH = math.asin(1 / math.sqrt(3))
MIN_PITCH = math.radians(12)
MAX_PITCH = math.radians(78)


class Camera:
    def __init__(self, yaw=ISO_YAW, pitch=ISO_PITCH):
        self.yaw, self.pitch = yaw, pitch

    def project(self, p, z=0.0):
        x, y = p
        across = x * math.cos(self.yaw) + y * math.sin(self.yaw)
        into = -x * math.sin(self.yaw) + y * math.cos(self.yaw)
        return (across * UNIT, (into * math.sin(self.pitch) - z * math.cos(self.pitch)) * UNIT)

    @property
    def to_camera(self):
        return (-math.sin(self.yaw) * math.cos(self.pitch),
                math.cos(self.yaw) * math.cos(self.pitch),
                math.sin(self.pitch))

    def depth(self, p, z=0.0):
        c = self.to_camera
        return p[0] * c[0] + p[1] * c[1] + z * c[2]

    def faces(self, n):
        c = self.to_camera
        return n[0] * c[0] + n[1] * c[1] + n[2] * c[2] > 0

    def ellipse(self, r):
        return (r * UNIT, r * UNIT * math.sin(self.pitch))


# --- Shading, transcribed --------------------------------------------------

# `SceneLight`, transcribed: the light travels with the camera. A fixed
# compass sun leaves a full quadrant of the orbit with both visible walls at
# ambient — see `SceneLightTests.aFixedSunWouldLeaveHalfTheOrbitFlat`.
LIGHT_ACROSS = math.sqrt(2) / 2
LIGHT_INTO = -0.05 * math.sqrt(2)
LIGHT_UP = 0.70


def to_sun(camera):
    right = (math.cos(camera.yaw), math.sin(camera.yaw))
    away = (-math.sin(camera.yaw), math.cos(camera.yaw))
    return (right[0] * LIGHT_ACROSS + away[0] * LIGHT_INTO,
            right[1] * LIGHT_ACROSS + away[1] * LIGHT_INTO,
            LIGHT_UP)


def shade(n, camera):
    L = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
    if L == 0:
        return 0
    sun = to_sun(camera)
    d = (n[0] * sun[0] + n[1] * sun[1] + n[2] * sun[2]) / L
    return (0.80 - (0.58 + 0.42 * max(0, d))) * 1.2


def tone(hexcol, sh):
    r, g, b = (hexcol >> 16) & 255, (hexcol >> 8) & 255, hexcol & 255
    f = 1 - sh if sh > 0 else 1
    r, g, b = r * f, g * f, b * f
    if sh < 0:
        w = -sh
        r, g, b = r + (255 - r) * w, g + (255 - g) * w, b + (255 - b) * w
    return "#%02x%02x%02x" % (int(max(0, min(255, r))), int(max(0, min(255, g))), int(max(0, min(255, b))))


def mid(a, b):
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def corners(cx, cy, w, h):
    hw, hh = w / 2, h / 2
    return [(cx - hw, cy - hh), (cx + hw, cy - hh), (cx + hw, cy + hh), (cx - hw, cy + hh)]


def wall_normal(a, b, centre=None):
    n = (b[1] - a[1], -(b[0] - a[0]), 0.0)
    if centre is None:
        return n
    mx, my = (a[0] + b[0]) / 2 - centre[0], (a[1] + b[1]) / 2 - centre[1]
    return (-n[0], -n[1], 0.0) if n[0] * mx + n[1] * my < 0 else n


def roof_normal(a, b, run, rise, centre=None):
    n = wall_normal(a, b, centre)
    L = math.hypot(n[0], n[1])
    if L == 0 or run <= 0:
        return (0, 0, 1)
    return (n[0] / L * rise, n[1] / L * rise, run)


# --- The deferred display list, transcribed --------------------------------

class Scene:
    """`AxoScene`: collect, sort far-to-near, tie-break on emission order."""

    def __init__(self, camera):
        self.camera = camera
        self.items = []
        self.checks = []

    def face(self, verts, fill, sh, outline=None, lw=0.7, depth=None):
        pts = [self.camera.project(p, z) for p, z in verts]
        d = depth if depth is not None else max(self.camera.depth(p, z) for p, z in verts)
        stroke = ' stroke="%s" stroke-width="%s"' % (outline, lw) if outline else ' stroke="none"'
        svg = '<polygon points="%s" fill="%s"%s/>' % (
            " ".join("%.2f,%.2f" % q for q in pts), tone(fill, sh), stroke)
        self.items.append((d, len(self.items), svg, verts))

    def ellipse(self, centre, z, r, fill, sh):
        cx, cy = self.camera.project(centre, z)
        rx, ry = self.camera.ellipse(r)
        self.items.append((self.camera.depth(centre, z), len(self.items),
                           '<ellipse cx="%.2f" cy="%.2f" rx="%.2f" ry="%.2f" fill="%s"/>'
                           % (cx, cy, rx, ry, tone(fill, sh)), None))

    def render(self):
        return [it for it in sorted(self.items, key=lambda it: (it[0], it[1]))]


def gabled(scene, cx, cy, w, h, base, eaves, ridge, wall, wall_outline, roof):
    cam = scene.camera
    cs = corners(cx, cy, w, h)
    eavesZ, ridgeZ = base + eaves, base + ridge
    alongX = w >= h
    if alongX:
        ridgeA, ridgeB = mid(cs[0], cs[3]), mid(cs[1], cs[2])
        longEdges = [(cs[0], cs[1]), (cs[3], cs[2])]
        gableEnds = [(cs[0], cs[3]), (cs[1], cs[2])]
    else:
        ridgeA, ridgeB = mid(cs[0], cs[1]), mid(cs[3], cs[2])
        longEdges = [(cs[0], cs[3]), (cs[1], cs[2])]
        gableEnds = [(cs[0], cs[1]), (cs[3], cs[2])]

    shown = 0
    for a, b in [(cs[0], cs[1]), (cs[1], cs[2]), (cs[2], cs[3]), (cs[3], cs[0])]:
        n = wall_normal(a, b, (cx, cy))
        if not cam.faces(n):
            continue
        shown += 1
        scene.face([(a, base), (b, base), (b, eavesZ), (a, eavesZ)], wall, shade(n, cam), wall_outline)
    scene.checks.append(("walls shown", shown))

    deck = 0.18
    for i, (e0, e1) in enumerate(gableEnds):
        n = wall_normal(e0, e1, (cx, cy))
        if not cam.faces(n):
            continue
        apex = ridgeA if i == 0 else ridgeB
        scene.face([(e0, eavesZ), (e1, eavesZ), (apex, ridgeZ - deck)], wall, shade(n, cam), wall_outline)

    run = min(w, h) / 2
    rise = max(0.1, ridge - eaves)
    overhang = min(0.45, run * 0.22)
    span = (ridgeB[0] - ridgeA[0], ridgeB[1] - ridgeA[1])
    L = math.hypot(*span)
    along = (span[0] / L * overhang, span[1] / L * overhang) if L > 0 else (0, 0)
    ridgeStart = (ridgeA[0] - along[0], ridgeA[1] - along[1])
    ridgeEnd = (ridgeB[0] + along[0], ridgeB[1] + along[1])

    ordered = sorted(longEdges, key=lambda e: cam.depth(mid(*e)))
    for planeIndex, (e0, e1) in enumerate(ordered):
        n = roof_normal(e0, e1, run, rise, (cx, cy))
        flat = math.hypot(n[0], n[1])
        out = (n[0] / flat * overhang, n[1] / flat * overhang) if flat > 0 else (0, 0)
        a = (e0[0] + out[0] - along[0], e0[1] + out[1] - along[1])
        b = (e1[0] + out[0] + along[0], e1[1] + out[1] + along[1])
        drop = eavesZ - overhang * (rise / max(run, 0.1)) + 0.04
        scene.face([(a, drop), (b, drop), (ridgeEnd, ridgeZ), (ridgeStart, ridgeZ)], roof, shade(n, cam), "#00000044")
        t = 0.18
        scene.face([(a, drop), (b, drop), (b, drop - t), (a, drop - t)], roof, 0.34)
        if planeIndex == len(ordered) - 1:
            scene.face([(a, drop), (ridgeStart, ridgeZ), (ridgeStart, ridgeZ - t), (a, drop - t)], roof, 0.26)
            scene.face([(b, drop), (ridgeEnd, ridgeZ), (ridgeEnd, ridgeZ - t), (b, drop - t)], roof, 0.26)


def block(scene, cx, cy, w, h, height, fill, outline):
    cam = scene.camera
    cs = corners(cx, cy, w, h)
    for a, b in [(cs[0], cs[1]), (cs[1], cs[2]), (cs[2], cs[3]), (cs[3], cs[0])]:
        n = wall_normal(a, b, (cx, cy))
        if cam.faces(n):
            scene.face([(a, 0), (b, 0), (b, height), (a, height)], fill, shade(n, cam), outline)
    scene.face([(p, height) for p in cs], fill, shade((0, 0, 1), cam), outline)


def cylinder(scene, cx, cy, r, height, fill, outline):
    cam = scene.camera
    ring = [(cx + math.cos(i / 24 * 2 * math.pi) * r, cy + math.sin(i / 24 * 2 * math.pi) * r) for i in range(24)]
    for i in range(24):
        a, b = ring[i], ring[(i + 1) % 24]
        n = wall_normal(a, b, (cx, cy))
        if cam.faces(n):
            scene.face([(a, 0), (b, 0), (b, height), (a, height)], fill, shade(n, cam))
    scene.ellipse((cx, cy), height, r, fill, shade((0, 0, 1), cam))


def fence(scene, a, b, posts=9):
    for i in range(posts):
        t = i / (posts - 1)
        p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        scene.face([((p[0] - 0.08, p[1] - 0.08), 0), ((p[0] + 0.08, p[1] - 0.08), 0),
                    ((p[0] + 0.08, p[1] - 0.08), 1.5), ((p[0] - 0.08, p[1] - 0.08), 1.5)],
                   0x8a6f4a, 0.1)


def ell(scene, cx, cy, w, h, base, eaves, ridge, wall, wall_outline, roof, fraction=0.45):
    """`LShape.wings` + two gabled buildings, transcribed.

    The wings butt rather than overlap, and because they are the same depth a
    common roof pitch puts their ridges at the same height, so the junction is
    a valley rather than two roofs crashing through each other.
    """
    depth = min(w, h) * fraction
    along = (cx, cy - h / 2 + depth / 2, w, depth)
    across = (cx - w / 2 + depth / 2, cy + depth / 2, depth, h - depth)
    cam = scene.camera
    for wx, wy, ww, wh in sorted([along, across], key=lambda g: cam.depth((g[0], g[1]))):
        gabled(scene, wx, wy, ww, wh, base, eaves, ridge, wall, wall_outline, roof)


def build(camera):
    scene = Scene(camera)
    plot = [(-14, -12), (16, -12), (16, 16), (-14, 16)]
    scene.face([(p, 0) for p in plot], 0x7ab648, -0.05, "#5e8c34", 1.0,
               depth=min(camera.depth(p) for p in plot) - 1000)
    gabled(scene, 0, 0, 6, 5, 0, 2.4, 3.8, 0xC8CDD2, "#7e858c", 0x4A5B6B)
    gabled(scene, 11, 2, 5, 9, 0, 2.6, 4.6, 0xF5E7C8, "#a08f6f", 0xC4553F)
    ell(scene, -6, 9, 14, 11, 0, 3.4, 6.4, 0xF5E7C8, "#a08f6f", 0xC4553F)
    block(scene, 7, -8, 4, 3, 2.2, 0xB9A882, "#8a7c5c")
    cylinder(scene, -10, -6, 1.6, 3.2, 0xA8B4BE, None)
    fence(scene, (-14, -12), (16, -12))
    return scene


# --- Checks ----------------------------------------------------------------

def check(camera, scene):
    problems = []
    for label, shown in scene.checks:
        if shown > 2:
            problems.append("%s: %d of 4 walls of a closed box are visible at once" % (label, shown))
        if shown < 1:
            problems.append("%s: no wall visible at all" % label)
    # Painter's order: nothing strictly nearer may be painted first.
    order = scene.render()
    worst = 0.0
    for i in range(1, len(order)):
        if order[i][0] < order[i - 1][0] - 1e-9:
            worst = max(worst, order[i - 1][0] - order[i][0])
    if worst > 0:
        problems.append("display list out of order by %.4f m" % worst)
    return problems


# --- Contact sheet ---------------------------------------------------------

CELL_W, CELL_H = 340, 300
COLS = 4


def main():
    views = [("yaw %d°" % round(math.degrees(y)), Camera(yaw=y)) for y in
             [ISO_YAW + i * math.pi / 4 for i in range(8)]]
    views += [("pitch %d° (low)" % round(math.degrees(MIN_PITCH)), Camera(ISO_YAW, MIN_PITCH)),
              ("pitch %d° (high)" % round(math.degrees(MAX_PITCH)), Camera(ISO_YAW, MAX_PITCH)),
              ("yaw 30° pitch 25°", Camera(math.radians(30), math.radians(25))),
              ("yaw 160° pitch 60°", Camera(math.radians(160), math.radians(60)))]

    rows = (len(views) + COLS - 1) // COLS
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">'
           % (COLS * CELL_W, rows * CELL_H),
           '<rect width="100%" height="100%" fill="#dfe8ef"/>']
    failures = []
    for index, (label, camera) in enumerate(views):
        scene = build(camera)
        problems = check(camera, scene)
        if problems:
            failures.append((label, problems))
        drawn = scene.render()
        pts = [camera.project(p, z) for _, _, _, verts in drawn if verts for p, z in verts]
        minx, maxx = min(q[0] for q in pts), max(q[0] for q in pts)
        miny, maxy = min(q[1] for q in pts), max(q[1] for q in pts)
        s = min((CELL_W - 24) / max(maxx - minx, 1e-6), (CELL_H - 44) / max(maxy - miny, 1e-6))
        ox = index % COLS * CELL_W + 12 - minx * s + ((CELL_W - 24) - (maxx - minx) * s) / 2
        oy = index // COLS * CELL_H + 32 - miny * s + ((CELL_H - 44) - (maxy - miny) * s) / 2
        out.append('<g transform="translate(%.2f,%.2f) scale(%.4f)">' % (ox, oy, s))
        out += [it[2] for it in drawn]
        out.append('</g>')
        out.append('<text x="%d" y="%d" font-family="sans-serif" font-size="13" fill="#1e2a33">%s%s</text>'
                   % (index % COLS * CELL_W + 12, index // COLS * CELL_H + 20,
                      label, "  ⚠︎" if problems else ""))
    out.append('</svg>')
    open("orbit.svg", "w").write("".join(out))

    try:
        import cairosvg
        cairosvg.svg2png(url="orbit.svg", write_to="orbit.png", output_width=COLS * CELL_W * 2)
    except Exception as error:  # noqa: BLE001
        print("no PNG (%s)" % error)

    for label, problems in failures:
        for problem in problems:
            print("FAIL %s: %s" % (label, problem))
    print("%d views, %d with problems" % (len(views), len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
