#!/usr/bin/env python3
"""Static checks for the app layer, which cannot be built or tested on Linux.

Three things, all of which have reached the user's Xcode as a build failure
rather than being caught here:

1. Every catalog type id named in the app layer must actually exist.
2. Every engine type the app names must be spelled the way it is declared —
   a type nested inside another (`Sizing.VocabularyTerm`) does not resolve
   from a bare `VocabularyTerm`.
3. Every function the app calls must be declared somewhere. Three times a
   scripted edit slicing between two anchors has swallowed a helper that
   happened to sit between them, leaving the call behind.
4. No one writes the camera's angles out by hand again.
5. Every file imports the module of every type it names.

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

    # Names the app declares itself shadow the engine's, legitimately — and a
    # Swift type is visible across its whole module, not just its own file.
    # Collecting these per file said `Massing` was unqualified in every file
    # but the one declaring it, which is nine false reports and a checker
    # nobody reads.
    declared = set()
    for path in APP.glob("*.swift"):
        declared |= set(re.findall(r"(?:enum|struct|final class|class) (\w+)", path.read_text()))

    failures = []
    for path in sorted(APP.glob("*.swift")):
        source = path.read_text()
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


# Names that are Swift, SwiftUI, Foundation or a local closure rather than
# something this repo declares. Deliberately short: anything else that shows up
# is either a real miss or a name worth adding here on purpose.
BUILTIN_CALLS = {
    "abs", "min", "max", "sqrt", "cos", "sin", "atan2", "floor", "ceil", "round",
    "print", "zip", "stride", "repeatElement", "swap", "type", "withAnimation",
    "assert", "precondition", "fatalError", "dump", "unsafeBitCast",
    # `#selector(...)` and `#keyPath(...)` are language constructs that read
    # as calls to a regex.
    "selector", "keyPath",
}

# `return (`, `for (`, `if let (` and friends all look like calls to a regex.
SWIFT_KEYWORDS = {
    "return", "let", "var", "for", "if", "guard", "while", "switch", "case",
    "in", "where", "throw", "try", "await", "is", "as", "init", "self", "super",
    "escaping", "inout", "some", "any", "func", "else", "do", "catch", "defer",
    "repeat", "subscript", "willSet", "didSet", "get", "set", "throws", "rethrows",
    "private", "public", "internal", "fileprivate", "open", "static", "class",
}


def declared_functions() -> set[str]:
    names: set[str] = set()
    for pattern in ("swift/Sources/Homestead*/*.swift", "Homestead/Homestead/*.swift"):
        for path in ROOT.glob(pattern):
            source = path.read_text()
            names |= set(re.findall(r"\bfunc (\w+)", source))
            # Enum cases with payloads are constructors.
            names |= set(re.findall(r"\bcase (\w+)\(", source))
            # Local closures and bindings are callable too.
            names |= set(re.findall(r"\blet (\w+): *\([^)]*\) *->", source))
    return names


def check_missing_calls() -> list[str]:
    """Calls to a lowercase name this repo neither declares nor inherits.

    Three times now a scripted edit that sliced between two anchors has
    swallowed a helper that happened to sit between them — `Palette`,
    `greenhouseInterior`, and a whole batch in `AxoKit` — leaving a call with
    no declaration. The file still parses; only Xcode notices, hours later.
    """
    known = declared_functions()
    failures = []
    for path in sorted(APP.glob("*.swift")):
        source = path.read_text()
        for line_number, line in enumerate(source.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for name in re.findall(r"(?<![\w.$])([a-z][A-Za-z0-9]*)\s*\(", line):
                if name in known or name in BUILTIN_CALLS or name in SWIFT_KEYWORDS:
                    continue
                failures.append(f"{path.relative_to(ROOT)}:{line_number}: calls \"{name}\" but nothing declares it")
    return failures


# The fixed isometric camera, in every disguise it wore. `Camera3D` replaced
# eighteen hand-written copies of it; three more survived the first sweep and
# were only found by grep afterwards — a negated visibility test, a grove sort
# and the plot slab's edge order. Each would have failed silently the moment
# the view was turned, which is the worst way for a thing to fail. Ask the
# camera instead: `camera.depthKey`, `camera.faces`, `camera.project`,
# `camera.horizontalEllipse`, or `painter.facesCamera` / `painter.depthOf`
# inside the kit.
HARDCODED_CAMERA = [
    (r"\b0\.866\b|\b1\.414\b", "the isometric projection's constants"),
    (r"\bAxonometry\b", "the camera type that was replaced"),
    # `a.x + a.y` as a value, which is the old depth key. Multiplication is
    # left alone: `n.x * n.x + n.y * n.y` is a length, not a camera.
    (r"(?<![\w.])[\w.$]+\.x \+ [\w.$]+\.y(?! \*)", "the old `x + y` depth sort or visibility test"),
]


def check_hardcoded_camera():
    """Flag any line that spells the fixed camera out instead of asking it."""
    failures = []
    for path in sorted(APP.glob("*.swift")):
        for line_number, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            for pattern, what in HARDCODED_CAMERA:
                if re.search(pattern, line):
                    failures.append(
                        f"{path.relative_to(ROOT)}:{line_number}: writes {what} by hand; ask the camera"
                    )
    return failures


# Which module each name comes from. Not every type — the ones that move
# between layers, which are the ones that get named in a file whose imports
# were written before they existed.
MODULE_OF = {
    "HomesteadCore": ["Camera3D", "SceneLight", "Viewport", "ProjectModel", "PlanStore"],
    "HomesteadEngine": ["PlanObject", "Transform", "Polygon", "LShape", "WaterfrontModel",
                        "Waterfront", "ObjectLibrary", "Placement", "Sizing", "Plot"],
    "SwiftUI": ["Color", "GraphicsContext", "StrokeStyle", "LinearGradient"],
}


def check_imports():
    """A type named without importing its module is a build failure, and
    `swiftc -parse` does not see it — it resolves nothing.

    Both of the ones this was written for were introduced by moving code
    between layers: `SceneLight` went from the app target to HomesteadCore
    and forty call sites in AxoKit kept compiling on Linux's parser alone,
    and `WaterLook` brought `Color` into a file that had never needed SwiftUI.
    """
    failures = []
    for path in sorted(APP.glob("*.swift")):
        source = path.read_text()
        imported = set(re.findall(r"^import (\w+)", source, re.M))
        body = "\n".join(
            line for line in source.splitlines() if not line.strip().startswith("//")
        )
        for module, names in MODULE_OF.items():
            if module in imported:
                continue
            for name in names:
                if re.search(r"(?<![\w.])" + name + r"\b", body):
                    failures.append(
                        f"{path.relative_to(ROOT)}: names `{name}` but does not import {module}"
                    )
                    break
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
    failures += check_missing_calls()
    failures += check_hardcoded_camera()
    failures += check_imports()

    for failure in failures:
        print(f"error: {failure}", file=sys.stderr)
    if failures:
        print(f"\n{len(failures)} problem{'' if len(failures) == 1 else 's'} in the app layer.", file=sys.stderr)
        return 1
    print(f"app layer ok ({len(known)} catalog type ids, {len(nested_engine_types())} nested engine types)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
