#!/usr/bin/env python3
"""Every catalog type id named in the app layer must actually exist.

The view layer keys several tables by type id — massing, materials, palettes,
cylinder caps, foliage. A typo or a renamed catalog entry makes the row
silently unreachable: the object still draws, in the fallback style, and
nothing anywhere says the entry was never used. Three of these were already
dead by the time this check was written ("root-cellar" for "cellar",
"battery" for "battery-room", "electrical-panel" for nothing at all).

The app target can't be built or tested on Linux, so this is a text check
rather than a test — but it runs everywhere, which a test of the app target
would not.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "swift/Sources/HomesteadEngine/ObjectLibrary.swift"
APP = ROOT / "Homestead/Homestead"

# Keys that are deliberately not catalog ids.
ALLOWED = {"light", "dark"}


def main() -> int:
    known = set(re.findall(r'id: "([a-z0-9\-]+)"', LIBRARY.read_text()))
    if not known:
        print(f"error: no type ids found in {LIBRARY}", file=sys.stderr)
        return 1

    failures = []
    for path in sorted(APP.glob("*.swift")):
        source = path.read_text()
        used = set(re.findall(r'"([a-z0-9][a-z0-9\-]*)":\s*(?:Palette|Surfaces|\.)', source))
        used |= set(re.findall(r'case "([a-z0-9][a-z0-9\-]*)"', source))
        for name in sorted(used - known - ALLOWED):
            failures.append(f"{path.relative_to(ROOT)}: \"{name}\" is not a catalog type id")

    for failure in failures:
        print(f"error: {failure}", file=sys.stderr)
    if failures:
        print(f"\n{len(failures)} unreachable table entr{'y' if len(failures) == 1 else 'ies'}.", file=sys.stderr)
        return 1
    print(f"type ids ok ({len(known)} in catalog)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
