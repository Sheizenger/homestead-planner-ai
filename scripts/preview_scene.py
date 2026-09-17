#!/usr/bin/env python3
"""Rasterise a built scene from the real meshes, on Linux.

The app target cannot be compiled here, let alone rendered, and the previous
3D pass proved three times over that reasoning about geometry without looking
at it produces confident wrong answers. So: `scene-dump` builds a real scene
with the real generator, this reads the same OBJ files the renderer will load,
transforms them by the same node transforms, projects them through the same
camera, samples the same colour atlas, and paints them back to front.

It is a transcription and it will drift from SceneKit in the details — no
shadows, no anti-aliasing, one light. It is not trying to be the renderer. It
is trying to answer "is the shed the size of a shed, is the tractor standing
on the ground, is the fence following the fence line", which are the questions
that have actually gone wrong.

    python3 scripts/preview_scene.py             # default camera
    python3 scripts/preview_scene.py --yaw 60    # from somewhere else
"""

import argparse
import json
import math
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODELS = ROOT / "Homestead" / "Homestead" / "Models3D"

UNIT = math.sqrt(2) * math.cos(math.pi / 6)
ISO_YAW = -math.pi / 4
ISO_PITCH = math.asin(1 / math.sqrt(3))
# `SceneLight.following` at the default camera, in engine axes.
TO_SUN = (0.45, -0.55, 0.70)


class Camera:
    def __init__(self, yaw=ISO_YAW, pitch=ISO_PITCH):
        self.yaw, self.pitch = yaw, pitch

    def project(self, x, y, z):
        """Scene space (X east, Y up, Z south) to the screen."""
        across = x * math.cos(self.yaw) + z * math.sin(self.yaw)
        into = -x * math.sin(self.yaw) + z * math.cos(self.yaw)
        return (across * UNIT, (into * math.sin(self.pitch) - y * math.cos(self.pitch)) * UNIT)

    @property
    def to_camera(self):
        return (-math.sin(self.yaw) * math.cos(self.pitch),
                math.sin(self.pitch),
                math.cos(self.yaw) * math.cos(self.pitch))

    def depth(self, x, y, z):
        c = self.to_camera
        return x * c[0] + y * c[1] + z * c[2]


_cache = {}


def load_obj(name):
    """Vertices, texture coordinates and triangles for one mesh."""
    if name in _cache:
        return _cache[name]
    path = MODELS / (name + ".obj")
    positions, uvs, faces = [], [], []
    if path.exists():
        for line in path.read_text().splitlines():
            if line.startswith("v "):
                positions.append(tuple(float(v) for v in line.split()[1:4]))
            elif line.startswith("vt "):
                uvs.append(tuple(float(v) for v in line.split()[1:3]))
            elif line.startswith("f "):
                corners = []
                for token in line.split()[1:]:
                    bits = token.split("/")
                    vertex = int(bits[0]) - 1
                    texture = int(bits[1]) - 1 if len(bits) > 1 and bits[1] else None
                    corners.append((vertex, texture))
                # Fan-triangulate; these kits are convex quads and triangles.
                for i in range(1, len(corners) - 1):
                    faces.append((corners[0], corners[i], corners[i + 1]))
    _cache[name] = (positions, uvs, faces)
    return _cache[name]


_atlases = {}


def atlas(kit):
    if kit in _atlases:
        return _atlases[kit]
    try:
        from PIL import Image
        path = MODELS / kit / "colormap.png"
        image = Image.open(path).convert("RGB")
        _atlases[kit] = (image.load(), image.size)
    except Exception:
        _atlases[kit] = None
    return _atlases[kit]


def sample(kit, uv):
    got = atlas(kit)
    if got is None or uv is None:
        return (170, 170, 170)
    pixels, (width, height) = got
    x = min(width - 1, max(0, int(uv[0] * width)))
    y = min(height - 1, max(0, int((1 - uv[1]) * height)))
    return pixels[x, y]


def shade(normal, colour, tint=None):
    length = math.sqrt(sum(c * c for c in normal)) or 1
    # The light is in engine axes; the scene's Y is the engine's Z.
    dot = (normal[0] * TO_SUN[0] + normal[2] * TO_SUN[1] + normal[1] * TO_SUN[2]) / length
    level = 0.55 + 0.45 * max(0.0, dot)
    r, g, b = colour
    if tint is not None and tint >= 0:
        # Multiply, as `SCNMaterial.multiply` does: the atlas keeps its own
        # light and shade and the tint recolours it. Blending toward the tint
        # instead floods the mesh and throws away every window and door.
        tr, tg, tb = (tint >> 16) & 255, (tint >> 8) & 255, tint & 255
        r, g, b = r * tr / 255, g * tg / 255, b * tb / 255
    return "#%02x%02x%02x" % tuple(min(255, max(0, int(v * level))) for v in (r, g, b))


def mesh_triangles(node, camera):
    positions, uvs, faces = load_obj(node["model"])
    if not faces:
        return []
    kit = node["model"].split("/")[0]
    sx, sy, sz = node["s"]
    px, py, pz = node["p"]
    cosine, sine = math.cos(node["yaw"]), math.sin(node["yaw"])
    pitch = node.get("pitch", 0.0)
    cp, sp = math.cos(pitch), math.sin(pitch)
    tint = node.get("tint", -1)

    placed = []
    for x, y, z in positions:
        x, y, z = x * sx, y * sy, z * sz
        # Tilt about the node's own X, then turn about Y — the order the
        # renderer applies them in.
        y, z = y * cp - z * sp, y * sp + z * cp
        placed.append((px + x * cosine + z * sine, py + y, pz - x * sine + z * cosine))

    out = []
    for corners in faces:
        p = [placed[c[0]] for c in corners]
        ux = (p[1][0] - p[0][0], p[1][1] - p[0][1], p[1][2] - p[0][2])
        vx = (p[2][0] - p[0][0], p[2][1] - p[0][1], p[2][2] - p[0][2])
        normal = (ux[1] * vx[2] - ux[2] * vx[1],
                  ux[2] * vx[0] - ux[0] * vx[2],
                  ux[0] * vx[1] - ux[1] * vx[0])
        c = camera.to_camera
        if normal[0] * c[0] + normal[1] * c[1] + normal[2] * c[2] <= 0:
            continue  # back face
        uv = None
        for corner in corners:
            if corner[1] is not None and corner[1] < len(uvs):
                uv = uvs[corner[1]]
                break
        depth = sum(camera.depth(*q) for q in p) / 3
        out.append(((1, depth), [camera.project(*q) for q in p], shade(normal, sample(kit, uv), tint)))
    return out


def slab_triangles(slab, camera):
    """A slab is a polygon with a top and, unless it is flat, four sides."""
    polygon = slab["polygon"]
    points = [(polygon[i], polygon[i + 1]) for i in range(0, len(polygon), 2)]
    if len(points) < 3:
        return []
    colour = slab["colour"]
    rgb = ((colour >> 16) & 255, (colour >> 8) & 255, colour & 255)
    top, thickness = slab["top"], slab["thickness"]
    out = []

    # A slab is flat ground: it sorts by how high it is, not by how far away.
    #
    # Sorting it with everything else is what made the barn's walls vanish.
    # The lawn is one quad the size of the plot, its average depth is the
    # middle of the plot, and a painter's algorithm therefore paints it over
    # every building standing further away than that. SceneKit has a depth
    # buffer and does not care; this transcription has to say so explicitly,
    # or it reports faults that are not there — which is worse than useless.
    def add(corners, normal, layer=0):
        depth = sum(camera.depth(*q) for q in corners) / len(corners)
        out.append(((layer, top, depth), [camera.project(*q) for q in corners], shade(normal, rgb)))

    add([(x, top, y) for x, y in points], (0, 1, 0))
    if thickness > 0.001:
        centre = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
        for i in range(len(points)):
            a, b = points[i], points[(i + 1) % len(points)]
            normal = (b[1] - a[1], 0.0, -(b[0] - a[0]))
            mid = ((a[0] + b[0]) / 2 - centre[0], (a[1] + b[1]) / 2 - centre[1])
            if normal[0] * mid[0] + normal[2] * mid[1] < 0:
                normal = (-normal[0], 0.0, -normal[2])
            c = camera.to_camera
            if normal[0] * c[0] + normal[2] * c[2] <= 0:
                continue
            add([(a[0], top, a[1]), (b[0], top, b[1]),
                 (b[0], top - thickness, b[1]), (a[0], top - thickness, a[1])], normal)
    return out


def solid_triangles(solid, camera):
    """A built volume: walls up from the footprint, then a flat lid or a ridge."""
    polygon = solid["polygon"]
    points = [(polygon[i], polygon[i + 1]) for i in range(0, len(polygon), 2)]
    if len(points) < 3:
        return []
    colour = solid["colour"]
    rgb = ((colour >> 16) & 255, (colour >> 8) & 255, colour & 255)
    base, wall, ridge = solid["base"], solid["wall"], solid["ridge"]
    out = []
    centre = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))

    def add(corners, normal):
        depth = sum(camera.depth(*q) for q in corners) / len(corners)
        out.append(((1, depth), [camera.project(*q) for q in corners], shade(normal, rgb)))

    for i in range(len(points)):
        a, b = points[i], points[(i + 1) % len(points)]
        normal = (b[1] - a[1], 0.0, -(b[0] - a[0]))
        mid = ((a[0] + b[0]) / 2 - centre[0], (a[1] + b[1]) / 2 - centre[1])
        if normal[0] * mid[0] + normal[2] * mid[1] < 0:
            normal = (-normal[0], 0.0, -normal[2])
        c = camera.to_camera
        if normal[0] * c[0] + normal[2] * c[2] <= 0:
            continue
        add([(a[0], base, a[1]), (b[0], base, b[1]),
             (b[0], base + wall, b[1]), (a[0], base + wall, a[1])], normal)

    top = base + wall
    if ridge <= 0.001:
        add([(x, top, y) for x, y in points], (0, 1, 0))
        return out

    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    alongX = (max(xs) - min(xs)) >= (max(ys) - min(ys))
    apex = top + ridge
    if alongX:
        ridge_a = (min(xs), apex, centre[1])
        ridge_b = (max(xs), apex, centre[1])
        eaves = [(min(xs), top, min(ys)), (max(xs), top, min(ys)),
                 (max(xs), top, max(ys)), (min(xs), top, max(ys))]
    else:
        ridge_a = (centre[0], apex, min(ys))
        ridge_b = (centre[0], apex, max(ys))
        eaves = [(min(xs), top, min(ys)), (max(xs), top, min(ys)),
                 (max(xs), top, max(ys)), (min(xs), top, max(ys))]
    add([eaves[0], eaves[1], ridge_b, ridge_a], (0, 0.7, -0.7) if alongX else (0.7, 0.7, 0))
    add([eaves[3], eaves[2], ridge_b, ridge_a], (0, 0.7, 0.7) if alongX else (-0.7, 0.7, 0))
    add([eaves[0], ridge_a, eaves[3]], (-1, 0, 0) if alongX else (0, 0, -1))
    add([eaves[1], ridge_b, eaves[2]], (1, 0, 0) if alongX else (0, 0, 1))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--yaw", type=float, default=math.degrees(ISO_YAW))
    parser.add_argument("--pitch", type=float, default=math.degrees(ISO_PITCH))
    parser.add_argument("--out", default="scene")
    parser.add_argument("--width", type=int, default=1500)
    parser.add_argument("--scene", default=None, help="a scene JSON to use instead of generating one")
    args = parser.parse_args()

    if args.scene:
        data = json.loads(pathlib.Path(args.scene).read_text())
    else:
        swift = "swift"
        for candidate in ("/opt/swift/usr/bin/swift", "swift"):
            if os.path.exists(candidate) or candidate == "swift":
                swift = candidate
                break
        dump = subprocess.run(
            [swift, "run", "-c", "release", "scene-dump"],
            cwd=ROOT / "swift", capture_output=True, text=True,
        )
        if dump.returncode != 0:
            print(dump.stderr[-2000:], file=sys.stderr)
            return 1
        data = json.loads(dump.stdout.strip().splitlines()[-1])

    camera = Camera(math.radians(args.yaw), math.radians(args.pitch))
    triangles = []
    for slab in data["slabs"]:
        triangles += slab_triangles(slab, camera)
    for solid in data.get("solids", []):
        triangles += solid_triangles(solid, camera)
    for node in data["meshes"]:
        triangles += mesh_triangles(node, camera)
    if not triangles:
        print("nothing to draw", file=sys.stderr)
        return 1
    triangles.sort(key=lambda t: (t[0][0],) + t[0][1:] + (0,) * (3 - len(t[0])))

    xs = [p[0] for _, pts, _ in triangles for p in pts]
    ys = [p[1] for _, pts, _ in triangles for p in pts]
    span = max(max(xs) - min(xs), 1e-6)
    scale = (args.width - 40) / span
    height = int((max(ys) - min(ys)) * scale) + 40

    body = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % (args.width, height),
            '<rect x="0" y="0" width="%d" height="%d" fill="#cfe0ee"/>' % (args.width, height),
            '',
            '<g transform="translate(%.2f,%.2f) scale(%.5f)">' % (20 - min(xs) * scale, 20 - min(ys) * scale, scale)]
    for _, points, colour in triangles:
        body.append('<polygon points="%s" fill="%s"/>'
                    % (" ".join("%.3f,%.3f" % p for p in points), colour))
    body.append("</g></svg>")

    svg = ROOT / (args.out + ".svg")
    svg.write_text("".join(body))
    print("%d triangles, %d meshes, %d slabs, %d solids -> %s" %
          (len(triangles), len(data["meshes"]), len(data["slabs"]),
           len(data.get("solids", [])), svg.name))
    try:
        import cairosvg
        cairosvg.svg2png(url=str(svg), write_to=str(ROOT / (args.out + ".png")), output_width=args.width)
    except Exception as error:
        print("no PNG (%s)" % error, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
