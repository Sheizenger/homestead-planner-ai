#!/usr/bin/env python3
"""Static checks for the app layer, which cannot be built or tested on Linux.

Two things, both of which have reached the user's Xcode as a build failure
rather than being caught here:

1. Every catalog type id named in the app layer must actually exist.
2. Every engine type the app names must be spelled the way it is declared —
   a type nested inside another (`Sizing.VocabularyTerm`) does not resolve
   from a bare `VocabularyTerm`.

On (1): the view layer keys several tables by type id — massing, materials, palettes,
cylinder caps, foliage. A typo or a renamed catalog entry makes the row
silently unreachable: the object still draws, in the fallback style, and
nothing anywhere says the entry was never used. Three of these were already
dead by the time this check was written ("root-cellar" for "cellar",
"battery" for "battery-room", "electrical-panel" for nothing at all).

The app target can't be built or tested on Linux, so these are text checks
rather than tests — but they run everywhere, which a test of the app target
would not. `swiftc -parse` is no substitute: it checks syntax only, and every
one of these failures parsed cleanly.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "swift/Sources/HomesteadEngine/ObjectLibrary.swift"
APP = ROOT / "Homestead/Homestead"

# Keys that are deliberately not catalog ids.
ALLOWED = {"light", "dark"}


def nested_engine_types() -> dict[str, str]:
    """Public types declared one level inside another public type."""
    nested: dict[str, str] = {}
    for path in sorted(ROOT.glob("swift/Sources/Homestead*/*.swift")):
        outer = None
        for line in path.read_text().splitlines():
            top = re.match(r"public (?:enum|struct|final class|class) (\w+)", line)
            if top:
                outer = top.group(1)
                continue
            inner = re.match(r"    public (?:enum|struct|final class|class) (\w+)", line)
            if inner and outer:
                nested[inner.group(1)] = outer
    return nested


def check_nested_types() -> list[str]:
    nested = nested_engine_types()
    if not nested:
        return []

    failures = []
    for path in sorted(APP.glob("*.swift")):
        source = path.read_text()
        # Names the app declares itself shadow the engine's, legitimately.
        declared = set(re.findall(r"(?:enum|struct|final class|class) (\w+)", source))
        for name, owner in sorted(nested.items()):
            if name in declared:
                continue
            # Type positions only: after a colon, inside brackets, or as a
            # return type. Anything else is a value expression or prose.
            pattern = r"(?:: *|\[|-> *|<)(?<![.\w])" + re.escape(name) + r"(?![\w])"
            for line_number, line in enumerate(source.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//"):
                    continue
                if re.search(pattern, line):
                    failures.append(
                        f"{path.relative_to(ROOT)}:{line_number}: "
                        f'"{name}" is nested in {owner} — write "{owner}.{name}"'
                    )
    return failures


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

    failures += check_nested_types()

    for failure in failures:
        print(f"error: {failure}", file=sys.stderr)
    if failures:
        print(f"\n{len(failures)} problem{'' if len(failures) == 1 else 's'} in the app layer.", file=sys.stderr)
        return 1
    print(f"app layer ok ({len(known)} catalog type ids, {len(nested_engine_types())} nested engine types)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
