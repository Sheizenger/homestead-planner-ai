#!/usr/bin/env python3
"""Draw the axonometric massing to an SVG, so its geometry can be *seen*.

The app target cannot be built or run on Linux, so for three rounds the
roofs were "fixed" by reading the code and reasoning about the projection.
All three were wrong. Transcribing the same arithmetic here and looking at
the output found both real faults in one pass:

  - `AxoLight.wallNormal` is only outward for one winding, and `longEdges`
    and `gableEnds` are ordered ridge-A-end-first, which reverses half of
    them. The second slope of every roof therefore had an inward normal: its
    overhang was pushed 0.45 m *inside* the wall (the gap at the gable) and
    it was lit as though facing the sun (the pale wedge).
  - The eaves were dropped 5 cm below the top of the wall, so the roof plane
    extended back to the wall line passed *under* it and the wall came
    through the roof at the gable.

This is a transcription, not the real renderer — it will drift. It is worth
keeping anyway: re-transcribe the piece under suspicion, look at it, and
only then edit Swift. Usage:

    python3 scripts/preview_massing.py && open massing.svg

Needs `cairosvg` only for the PNG; the SVG itself has no dependencies.
"""

import math

COS, SIN = 0.866, 0.5
SCALE = 26.0
OX, OY = 420, 380

def proj(p, z=0.0):
    x, y = p
    return (OX + (x - y) * COS * SCALE, OY + ((x + y) * SIN - z) * SCALE)

def mid(a, b): return ((a[0]+b[0])/2, (a[1]+b[1])/2)
def depth(e): return (e[0][0]+e[0][1]+e[1][0]+e[1][1])/2

def corners(cx, cy, w, h):
    hw, hh = w/2, h/2
    return [(cx-hw, cy-hh), (cx+hw, cy-hh), (cx+hw, cy+hh), (cx-hw, cy+hh)]

def wall_normal(a, b, centre=None):
    n = (b[1]-a[1], -(b[0]-a[0]), 0.0)
    if centre is None: return n
    mx = (a[0]+b[0])/2 - centre[0]; my = (a[1]+b[1])/2 - centre[1]
    if n[0]*mx + n[1]*my < 0: return (-n[0], -n[1], 0.0)
    return n

def roof_normal(a, b, run, rise, centre=None):
    n = wall_normal(a, b, centre)
    L = math.hypot(n[0], n[1])
    if L == 0 or run <= 0: return (0,0,1)
    return (n[0]/L*rise, n[1]/L*rise, run)

TO_SUN = (0.45, -0.55, 0.70)
def shade(n):
    L = math.sqrt(n[0]**2+n[1]**2+n[2]**2)
    if L == 0: return 0
    d = (n[0]*TO_SUN[0]+n[1]*TO_SUN[1]+n[2]*TO_SUN[2])/L
    b = 0.58 + 0.42*max(0, d)
    return (0.80 - b)*1.2

def tone(hexcol, sh):
    r = (hexcol>>16)&255; g=(hexcol>>8)&255; b=hexcol&255
    if sh > 0: f = 1-sh
    else: f = 1
    r, g, b = r*f, g*f, b*f
    if sh < 0:
        w = -sh
        r = r + (255-r)*w; g = g + (255-g)*w; b = b + (255-b)*w
    return f"#{int(r):02x}{int(g):02x}{int(b):02x}"

OUT = []
def face(verts, fill, sh, outline=None, lw=0.7):
    pts = " ".join(f"{proj(p,z)[0]:.2f},{proj(p,z)[1]:.2f}" for p, z in verts)
    stroke = f' stroke="{outline}" stroke-width="{lw}"' if outline else ' stroke="none"'
    OUT.append(f'<polygon points="{pts}" fill="{tone(fill, sh)}"{stroke}/>')

def gabled(cx, cy, w, h, base, eaves, ridge, wall, wall_outline, roof):
    cs = corners(cx, cy, w, h)
    eavesZ, ridgeZ = base+eaves, base+ridge
    alongX = w >= h
    if alongX:
        ridgeA, ridgeB = mid(cs[0],cs[3]), mid(cs[1],cs[2])
        longEdges = [(cs[0],cs[1]), (cs[3],cs[2])]
        gableEnds = [(cs[0],cs[3]), (cs[1],cs[2])]
    else:
        ridgeA, ridgeB = mid(cs[0],cs[1]), mid(cs[3],cs[2])
        longEdges = [(cs[0],cs[3]), (cs[1],cs[2])]
        gableEnds = [(cs[0],cs[1]), (cs[3],cs[2])]

    walls = sorted([(cs[0],cs[1]),(cs[1],cs[2]),(cs[2],cs[3]),(cs[3],cs[0])], key=depth)
    for a, b in walls:
        face([(a,base),(b,base),(b,eavesZ),(a,eavesZ)], wall, shade(wall_normal(a,b,(cx,cy))), wall_outline)

    deck = 0.18
    for i, (e0, e1) in enumerate(gableEnds):
        apex = ridgeA if i == 0 else ridgeB
        face([(e0,eavesZ),(e1,eavesZ),(apex,ridgeZ-deck),(apex,ridgeZ-deck)], wall, shade(wall_normal(e0,e1,(cx,cy))), wall_outline)

    run = min(w,h)/2
    rise = max(0.1, ridge-eaves)
    overhang = min(0.45, run*0.22)
    span = (ridgeB[0]-ridgeA[0], ridgeB[1]-ridgeA[1])
    L = math.hypot(*span)
    along = (span[0]/L*overhang, span[1]/L*overhang) if L > 0 else (0,0)
    ridgeStart = (ridgeA[0]-along[0], ridgeA[1]-along[1])
    ridgeEnd = (ridgeB[0]+along[0], ridgeB[1]+along[1])

    ordered = sorted(longEdges, key=depth)
    for planeIndex, (e0, e1) in enumerate(ordered):
        n = roof_normal(e0, e1, run, rise, (cx,cy))
        flat = math.hypot(n[0], n[1])
        out = (n[0]/flat*overhang, n[1]/flat*overhang) if flat > 0 else (0,0)
        a = (e0[0]+out[0]-along[0], e0[1]+out[1]-along[1])
        b = (e1[0]+out[0]+along[0], e1[1]+out[1]+along[1])
        drop = eavesZ - overhang*(rise/max(run,0.1)) + 0.04
        face([(a,drop),(b,drop),(ridgeEnd,ridgeZ),(ridgeStart,ridgeZ)], roof, shade(n), "#00000044")
        t = 0.18
        face([(a,drop),(b,drop),(b,drop-t),(a,drop-t)], roof, 0.34)
        if planeIndex == len(ordered) - 1:
            face([(a,drop),(ridgeStart,ridgeZ),(ridgeStart,ridgeZ-t),(a,drop-t)], roof, 0.26)
            face([(b,drop),(ridgeEnd,ridgeZ),(ridgeEnd,ridgeZ-t),(b,drop-t)], roof, 0.26)

OUT.append('<rect width="840" height="620" fill="#7ab648"/>')
gabled(0, 0, 6, 5, 0, 2.4, 3.8, 0xC8CDD2, "#7e858c", 0x4A5B6B)
gabled(12, 0, 5, 8, 0, 2.4, 3.8, 0xF5E7C8, "#a08f6f", 0xC4553F)
gabled(0, 11, 12, 10, 0, 3.4, 6.4, 0xF5E7C8, "#a08f6f", 0xC4553F)
open('massing.svg','w').write(
    '<svg xmlns="http://www.w3.org/2000/svg" width="840" height="620">' + "".join(OUT) + '</svg>')
print("written")
