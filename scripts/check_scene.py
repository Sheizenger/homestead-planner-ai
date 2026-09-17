#!/usr/bin/env python3
"""Find meshes that pass through each other, and surfaces that fight for depth.

Interpenetration is the one class of fault a scene builder produces that no
unit test notices and no amount of reading catches: every object is correctly
placed *on its own terms*, and two of them happen to occupy the same cubic
metre. It shows up immediately to anyone looking at the result, which is how
this list was arrived at.

Boxes are axis-aligned and therefore generous — a box overlap is not proof
that the meshes touch. The thresholds are set so that what it reports is worth
looking at, and every fix is confirmed by rendering.

    python3 scripts/check_scene.py [scene.json]
"""

import json
import math
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def metrics():
    text = (ROOT / "swift/Sources/HomesteadCore/ModelMetrics.swift").read_text()
    table = {}
    for line in text[text.index('table = """'):].splitlines()[1:]:
        field = line.split()
        # At least seven: the box, and then however many profile columns the
        # generator writes. Requiring exactly seven is how this checker went
        # blind the day the profile was added — it read an empty table and
        # reported a clean scene for every scene.
        if len(field) >= 7:
            table[field[0]] = [float(v) for v in field[1:7]]
    if len(table) < 100:
        raise SystemExit("error: only %d meshes parsed out of ModelMetrics.swift" % len(table))
    return table


def box_of(node, table):
    bounds = table.get(node["model"])
    if not bounds:
        return None
    sx, sy, sz = node["s"]
    px, py, pz = node["p"]
    cosine, sine = math.cos(node["yaw"]), math.sin(node["yaw"])
    xs, zs = [], []
    for x in (bounds[0] * sx, bounds[1] * sx):
        for z in (bounds[4] * sz, bounds[5] * sz):
            xs.append(px + x * cosine + z * sine)
            zs.append(pz - x * sine + z * cosine)
    return (min(xs), max(xs), py + bounds[2] * sy, py + bounds[3] * sy, min(zs), max(zs))


def intersection(a, b):
    x = min(a[1], b[1]) - max(a[0], b[0])
    y = min(a[3], b[3]) - max(a[2], b[2])
    z = min(a[5], b[5]) - max(a[4], b[4])
    return 0 if x <= 0 or y <= 0 or z <= 0 else x * y * z


def volume(a):
    return max(0.0, a[1] - a[0]) * max(0.0, a[3] - a[2]) * max(0.0, a[5] - a[4])


def point_in(point, polygon):
    x, y = point
    inside = False
    for i in range(len(polygon)):
        ax, ay = polygon[i]
        bx, by = polygon[(i + 1) % len(polygon)]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay + 1e-30) + ax:
            inside = not inside
    return inside


def segments_cross(a, b, c, d):
    def side(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    d1, d2 = side(c, d, a), side(c, d, b)
    d3, d4 = side(a, b, c), side(a, b, d)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


def shrunk(polygon, by=0.05):
    """Pulled in toward its own centre, so touching does not read as overlap.

    The lawn stops exactly where the river bank starts, and a strict
    point-in-polygon test on a shared edge answers whichever way the
    floating point falls. A five-centimetre inset makes the question the one
    actually being asked: do these two share any *area*."""
    cx = sum(p[0] for p in polygon) / len(polygon)
    cy = sum(p[1] for p in polygon) / len(polygon)
    out = []
    for x, y in polygon:
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        f = max(0.0, (d - by)) / d if d > by else 0.0
        out.append((cx + dx * f, cy + dy * f))
    return out


def polygons_overlap(a, b):
    """Two flat polygons sharing area, not merely an edge."""
    if len(a) < 3 or len(b) < 3:
        return False
    a, b = shrunk(a), shrunk(b)
    if any(point_in(p, b) for p in a) or any(point_in(p, a) for p in b):
        return True
    for i in range(len(a)):
        for j in range(len(b)):
            if segments_cross(a[i], a[(i + 1) % len(a)], b[j], b[(j + 1) % len(b)]):
                return True
    return False


def main():
    if len(sys.argv) > 1:
        scene = json.loads(pathlib.Path(sys.argv[1]).read_text())
    else:
        dump = subprocess.run(
            ["swift", "run", "-c", "release", "scene-dump"],
            cwd=ROOT / "swift", capture_output=True, text=True,
        )
        if dump.returncode != 0:
            print(dump.stderr[-1500:], file=sys.stderr)
            return 1
        scene = json.loads(dump.stdout.strip().splitlines()[-1])

    table = metrics()
    types = {o["id"]: o["type"] for o in scene["objects"]}
    nodes = [n for n in scene["meshes"] if n.get("object")]
    boxes = {n["id"]: box_of(n, table) for n in nodes}

    problems = []

    # 1. Two different objects sharing space. Nothing the placer produces
    #    should do this — except a roof-mounted thing, which is *supposed* to
    #    be inside its host and has to be lifted onto the roof instead.
    for i, a in enumerate(nodes):
        for b in nodes[i + 1:]:
            if a["object"] == b["object"]:
                continue
            ba, bb = boxes[a["id"]], boxes[b["id"]]
            if not ba or not bb:
                continue
            shared = intersection(ba, bb)
            # Absolute *or* relative: a solar array is a few centimetres thick,
            # so being wholly inside a house is a tenth of a cubic metre and
            # slips under any volume threshold worth setting for buildings.
            if shared > 0.5 or shared > 0.25 * min(volume(ba), volume(bb)):
                problems.append(
                    "%s passes through %s (%.2f m3, %.0f%% of the smaller)"
                    % (types.get(a["object"], "?"), types.get(b["object"], "?"),
                       shared, 100 * shared / max(1e-9, min(volume(ba), volume(bb))))
                )

    # 2. A prop standing inside the thing it belongs to — a tractor halfway
    #    into the barn wall, which is the commonest fault of the lot.
    #
    #    Asked of the object's own plan footprint rather than of its meshes.
    #    A field's meshes are its plants, so a bale at the edge of a field
    #    touching a plant came out as "the bale is inside the field", which is
    #    not the question. `-inprop` is a prop put under its object on
    #    purpose — stools beneath an open canopy — and the builder says so in
    #    the id, because no box test can tell that from a mistake.
    plan = {
        o["id"]: [
            (o["x"] - o["w"] / 2, o["y"] - o["d"] / 2), (o["x"] + o["w"] / 2, o["y"] - o["d"] / 2),
            (o["x"] + o["w"] / 2, o["y"] + o["d"] / 2), (o["x"] - o["w"] / 2, o["y"] + o["d"] / 2),
        ]
        for o in scene["objects"] if abs(o.get("rot", 0)) < 1e-6
    }
    for a in nodes:
        if "-prop" not in a["id"]:
            continue
        footprint = plan.get(a["object"])
        box = boxes[a["id"]]
        if not footprint or not box:
            continue
        centre = ((box[0] + box[1]) / 2, (box[4] + box[5]) / 2)
        if point_in(centre, footprint):
            problems.append(
                "%s: its %s stands inside it"
                % (types.get(a["object"], "?"), a["model"].split("/")[-1])
            )

    # 3. Props of one object piled into each other.
    props = [n for n in nodes if "-prop" in n["id"]]
    for i, a in enumerate(props):
        for b in props[i + 1:]:
            if a["object"] != b["object"] or a["model"] != b["model"]:
                continue
            ba, bb = boxes[a["id"]], boxes[b["id"]]
            if not ba or not bb:
                continue
            shared = intersection(ba, bb)
            if shared > 0.35 * min(volume(ba), volume(bb)):
                problems.append(
                    "%s: its %s are piled into each other (%.1f m3)"
                    % (types.get(a["object"], "?"), a["model"].split("/")[-1], shared)
                )
                break

    # 4. Flat surfaces that overlap at the same height. Two coplanar faces
    #    have no depth order, so a renderer picks per pixel and the seam
    #    crawls — the "texture layering" that shows as a shimmering edge.
    #
    #    Same height alone is not enough to report: the lawn and the river
    #    bank are both at grade and sit side by side, and saying so every
    #    time is how a checker gets ignored.
    slabs = [
        (s["id"], s["top"], s["colour"],
         [(s["polygon"][i], s["polygon"][i + 1]) for i in range(0, len(s["polygon"]), 2)])
        for s in scene["slabs"]
    ]
    for i, (ida, topa, ca, pa) in enumerate(slabs):
        for idb, topb, cb, pb in slabs[i + 1:]:
            if ca == cb or abs(topa - topb) > 0.01:
                continue
            if polygons_overlap(pa, pb):
                problems.append(
                    "%s and %s overlap at the same height (%.2f m) and will fight for depth"
                    % (ida, idb, topa)
                )

    seen = set()
    unique = [p for p in problems if not (p in seen or seen.add(p))]
    for problem in unique:
        print("  " + problem)
    print("%d problems (%d meshes, %d slabs)" % (len(unique), len(nodes), len(scene["slabs"])))
    return 1 if unique else 0


if __name__ == "__main__":
    sys.exit(main())
