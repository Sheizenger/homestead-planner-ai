#!/usr/bin/env python3
"""Fetch the CC0 model kits the 3D view is built from, and vendor them.

The scene is drawn with real meshes rather than hand-drawn paths, and the
meshes come from Kenney's asset kits: CC0, so there is nothing to attribute
and nothing to license, low-poly and flat-shaded, which is the look the
references have.

They are vendored rather than fetched at build time — a build that needs the
network is a build that breaks when the network does — but the script stays,
so the set can be re-derived, extended, or audited against upstream.

Each kit ships one `colormap.png` atlas and one material for the whole kit,
which is why a scene of two hundred objects costs one texture and one
material. OBJs are normalised on the way in: Kenney writes `v x y z r g b`,
and the three trailing vertex colours are not standard OBJ, are redundant
beside the atlas, and are one more thing for ModelIO to disagree about.

    python3 scripts/vendor_models.py            # fetch anything missing
    python3 scripts/vendor_models.py --check    # verify what is vendored
    python3 scripts/vendor_models.py --force    # re-fetch everything
"""

import argparse
import hashlib
import io
import json
import pathlib
import shutil
import sys
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / "Homestead" / "Homestead" / "Models3D"

# Pinned to the exact upload each URL points at. Kenney's download links carry
# a content hash, so a URL that still resolves is the file that was reviewed.
KITS = {
    "city": {
        "url": "https://kenney.nl/media/pages/assets/city-kit-suburban/2c871b7af2-1745479373/kenney_city-kit-suburban_20.zip",
        "credit": "Kenney — City Kit (Suburban)",
        # Houses, fences, paths, driveways and street trees: the whole kit is
        # on-subject, so all of it comes in.
        "models": "all",
    },
    "town": {
        "url": "https://kenney.nl/media/pages/assets/fantasy-town-kit/efe948d309-1754222374/kenney_fantasy-town-kit_2.0.zip",
        "credit": "Kenney — Fantasy Town Kit",
        # The modular walls and roofs a building is assembled from, plus the
        # watermill and the windmill, which are the two pieces of kit on a
        # homestead that nothing else could stand in for.
        "models": "all",
    },
    "forest": {
        "url": "https://kenney.nl/media/pages/assets/mini-forest/44a89aed7f-1784024079/kenney_mini-forest_1.0.zip",
        "credit": "Kenney — Mini Forest",
        "models": "all",
    },
    "survival": {
        "url": "https://kenney.nl/media/pages/assets/survival-kit/4065a8185b-1712149243/kenney_survival-kit.zip",
        "credit": "Kenney — Survival Kit",
        "models": "all",
    },
    "water": {
        "url": "https://kenney.nl/media/pages/assets/watercraft-kit/a335cfed49-1713519620/kenney_watercraft-pack.zip",
        "credit": "Kenney — Watercraft Kit",
        # A homestead dock takes a rowing boat and a ramp, not an ocean liner.
        "models": [
            "boat-fishing-small", "boat-row-large", "boat-row-small",
            "boat-sail-a", "boat-house-a", "buoy", "buoy-flag",
            "ramp", "ramp-wide",
        ],
    },
    "works": {
        "url": None,  # resolved from the asset page; see resolve_url
        "page": "https://kenney.nl/assets/factory-kit",
        "credit": "Kenney — Factory Kit",
        # Tanks, silos, cisterns and the plant rooms: hoppers and structures.
        "models": [
            "hopper-high-round", "hopper-high-square", "hopper-round", "hopper-square",
            "machine", "machine-bed", "machine-fortified", "machine-window",
            "structure-short", "structure-medium", "structure-high", "structure-tall",
            "structure-wall", "structure-doorway", "structure-doorway-wide",
            "structure-window", "structure-window-wide",
            "pipe-large", "pipe-large-bend", "pipe-large-valve",
            "top", "top-large", "door-wide-closed",
        ],
    },
    "yard": {
        "url": None,
        "page": "https://kenney.nl/assets/graveyard-kit",
        "credit": "Kenney — Graveyard Kit",
        # Hay bales, conifers, stone walls and iron railings — the farmyard
        # furniture the other kits have no answer for.
        "models": [
            "hay-bale", "hay-bale-bundled", "pine", "pine-crooked",
            "pine-fall", "pine-fall-crooked", "rocks", "rocks-tall",
            "stone-wall", "stone-wall-column", "stone-wall-curve",
            "iron-fence", "iron-fence-bar", "iron-fence-curve",
            "iron-fence-border", "iron-fence-border-gate", "iron-fence-border-column",
            "fence", "fence-gate", "fence-damaged",
            "lightpost-single", "lightpost-double", "bench",
            "pumpkin", "pumpkin-tall", "trunk-long", "debris-wood", "shovel",
        ],
    },
    "vehicles": {
        "url": None,
        "page": "https://kenney.nl/assets/car-kit",
        "credit": "Kenney — Car Kit",
        # A car on the drive and a tractor by the barn is most of what makes a
        # site read as lived in rather than as a model of one.
        "models": [
            "sedan", "suv", "van", "truck", "truck-flat", "delivery",
            "tractor", "tractor-shovel",
            "wheel-default", "wheel-truck", "wheel-tractor-front", "wheel-tractor-back",
        ],
    },
}

LICENSE = """# Third-party models

Every mesh under this directory comes from one of Kenney's asset kits and is
released under **CC0 1.0 Universal** (public domain dedication): free to use,
modify and redistribute, commercially or not, with no attribution required.

Attribution is given anyway, because it is deserved and because it records
where these came from if they ever need re-deriving.

Source: https://kenney.nl/  ·  License: https://creativecommons.org/publicdomain/zero/1.0/

`scripts/vendor_models.py` fetched them; `manifest.json` beside this file
pins the exact upload each kit came from, with a checksum.

## Kits
"""


def resolve_url(kit):
    if kit.get("url"):
        return kit["url"]
    import re
    page = urllib.request.urlopen(kit["page"], timeout=60).read().decode("utf8", "replace")
    found = re.search(r"https://kenney\.nl/media/pages/assets/[^\"' ]*\.zip", page)
    if not found:
        raise SystemExit("no download link on " + kit["page"])
    return found.group(0)


def normalise_obj(text):
    """Standard OBJ, four significant figures, no comments.

    Kenney's `v x y z r g b` carries per-vertex colours that the colormap
    atlas already provides. Keeping them risks a loader reading the extra
    components as something else, and drops nothing.
    """
    out = []
    for line in text.splitlines():
        if line.startswith("v "):
            parts = line.split()
            out.append("v " + " ".join("%.5g" % float(p) for p in parts[1:4]))
        elif line.startswith(("vn ", "vt ")):
            parts = line.split()
            out.append(parts[0] + " " + " ".join("%.5g" % float(p) for p in parts[1:]))
        elif line.startswith("#") or not line.strip():
            continue
        else:
            out.append(line)
    return "\n".join(out) + "\n"


def vendor(name, kit, force):
    target = DEST / name
    if target.exists() and not force:
        return None
    url = resolve_url(kit)
    print("fetching %s ..." % name, flush=True)
    blob = urllib.request.urlopen(url, timeout=300).read()
    digest = hashlib.sha256(blob).hexdigest()

    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)

    wanted = kit["models"]
    written = []
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        for entry in archive.namelist():
            path = pathlib.PurePosixPath(entry)
            if "OBJ format" not in entry:
                continue
            if path.name.lower() == "colormap.png":
                (target / "colormap.png").write_bytes(archive.read(entry))
                continue
            if path.suffix not in (".obj", ".mtl"):
                continue
            if wanted != "all" and path.stem not in wanted:
                continue
            if path.suffix == ".obj":
                (target / path.name).write_text(normalise_obj(archive.read(entry).decode("utf8", "replace")))
                written.append(path.stem)
            else:
                # The material file is three lines and names the atlas; rewrite
                # it so the texture sits beside the model rather than in a
                # Textures/ subfolder that only existed in the zip.
                (target / path.name).write_text(
                    "newmtl colormap\nKd 1 1 1\nmap_Kd colormap.png\n"
                )
    if wanted != "all":
        missing = sorted(set(wanted) - set(written))
        if missing:
            raise SystemExit("%s: kit has no %s" % (name, ", ".join(missing)))
    return {"url": url, "sha256": digest, "credit": kit["credit"], "models": len(written)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        problems = []
        for name in KITS:
            kit_dir = DEST / name
            if not kit_dir.is_dir():
                problems.append("%s is not vendored" % name)
                continue
            if not (kit_dir / "colormap.png").exists():
                problems.append("%s has no colormap.png" % name)
            if not list(kit_dir.glob("*.obj")):
                problems.append("%s has no models" % name)
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        if problems:
            return 1
        total = len(list(DEST.glob("*/*.obj")))
        print("models ok (%d meshes in %d kits)" % (total, len(KITS)))
        return 0

    DEST.mkdir(parents=True, exist_ok=True)
    manifest_path = DEST / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for name, kit in KITS.items():
        record = vendor(name, kit, args.force)
        if record:
            manifest[name] = record
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    lines = [LICENSE]
    for name in sorted(manifest):
        record = manifest[name]
        lines.append("- **%s** — %s (%d meshes)" % (name, record["credit"], record["models"]))
    (DEST / "LICENSE.md").write_text("\n".join(lines) + "\n")

    print("vendored %d meshes in %d kits" % (len(list(DEST.glob("*/*.obj"))), len(KITS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
