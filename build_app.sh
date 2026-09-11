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
