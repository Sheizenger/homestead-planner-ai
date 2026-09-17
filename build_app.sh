#!/usr/bin/env bash
#
# Build, check, install and run the macOS app without touching Xcode's UI.
#
#   ./build_app.sh                  build the app
#   ./build_app.sh --run            build, then launch it
#   ./build_app.sh --install --run  build, copy to /Applications, launch it
#   ./build_app.sh --self-check     run the engine test suite, then build
#   ./build_app.sh --clean          delete build output first
#
# Requires macOS with Xcode installed. The engine/core test suite (--self-check)
# also runs on Linux, where the app itself cannot be built at all.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/Homestead/Homestead.xcodeproj"
TARGET="Homestead"
CONFIGURATION="Debug"
BUILD_DIR="$ROOT/build/xcode"
APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$TARGET.app"

DO_RUN=0
DO_INSTALL=0
DO_SELF_CHECK=0
DO_CLEAN=0

for arg in "$@"; do
    case "$arg" in
        --run) DO_RUN=1 ;;
        --install) DO_INSTALL=1 ;;
        --self-check) DO_SELF_CHECK=1 ;;
        --clean) DO_CLEAN=1 ;;
        --release) CONFIGURATION="Release"; APP_PATH="$BUILD_DIR/Build/Products/Release/$TARGET.app" ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ -d "$PROJECT" ] || fail "no Xcode project at $PROJECT"

if [ "$DO_CLEAN" = 1 ]; then
    step "Cleaning $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

if [ "$DO_SELF_CHECK" = 1 ]; then
    step "Engine + core test suite (swift test)"
    swift test --package-path "$ROOT/swift"

    # The app target can't be tested on Linux, so the app-layer bugs that are
    # checkable as text get checked here: tables keyed by a catalog type id
    # that doesn't exist, and engine types named without the type they are
    # nested in. Both have reached Xcode as build failures.
    step "App-layer static checks"
    python3 "$ROOT/scripts/check_type_ids.py"

    # The view's geometry transcribed and rendered from a dozen camera angles.
    # It writes a contact sheet to look at, and fails on the two things worth
    # asserting without eyes: a face drawn as visible that is turned away, and
    # a display list that paints something over what is nearer to the camera.
    step "Orbit geometry"
    python3 "$ROOT/scripts/preview_orbit.py"

    # The 3D meshes: all present, and measured into a table that matches them.
    step "Models"
    python3 "$ROOT/scripts/vendor_models.py" --check
    python3 "$ROOT/scripts/build_model_metrics.py" --check

    # A whole generated plan, built into a scene and rasterised from the real
    # meshes. Writes scene.png; the questions it answers — is the shed the
    # size of a shed, is the tractor on the ground, does the river appear —
    # are the ones that have actually gone wrong.
    step "Scene preview"
    python3 "$ROOT/scripts/preview_scene.py"
fi

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found — this part needs macOS with Xcode"

# A scheme only exists here if it was marked Shared in Xcode; -target always
# works, so fall back to it rather than failing on a fresh clone.
BUILD_SELECTOR=(-target "$TARGET")
if xcodebuild -project "$PROJECT" -list 2>/dev/null | sed -n '/Schemes:/,$p' | grep -qw "$TARGET"; then
    BUILD_SELECTOR=(-scheme "$TARGET")
fi

step "Building $TARGET ($CONFIGURATION)"
xcodebuild \
    -project "$PROJECT" \
    "${BUILD_SELECTOR[@]}" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    build

[ -d "$APP_PATH" ] || fail "build reported success but $APP_PATH is missing"
printf '\nbuilt: %s\n' "$APP_PATH"

if [ "$DO_INSTALL" = 1 ]; then
    step "Installing to /Applications"
    rm -rf "/Applications/$TARGET.app"
    cp -R "$APP_PATH" "/Applications/$TARGET.app"
    APP_PATH="/Applications/$TARGET.app"
    printf 'installed: %s\n' "$APP_PATH"
fi

if [ "$DO_RUN" = 1 ]; then
    step "Launching"
    open "$APP_PATH"
fi
