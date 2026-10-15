#!/usr/bin/env bash
# Shared helpers for SpaceSweep build scripts. Source, don't execute.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_NAME="SpaceSweep"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"

die() { echo "error: $*" >&2; exit 1; }

# Removes a generated directory or file, but only if it resolves to a path inside
# this repository's build/ or dist/ folder. Never touches anything else.
safe_remove_generated() {
    local target="$1"
    [[ -n "$target" ]] || die "safe_remove_generated: empty path"
    [[ -e "$target" || -L "$target" ]] || return 0
    local parent resolved
    parent="$(cd "$(dirname "$target")" && pwd -P)"
    resolved="$parent/$(basename "$target")"
    case "$resolved" in
        "$BUILD_DIR"|"$DIST_DIR") ;;  # the folders themselves are fine
        "$BUILD_DIR"/*|"$DIST_DIR"/*) ;;
        *) die "refusing to remove '$resolved' (outside build/ and dist/)" ;;
    esac
    [[ "$resolved" != "/" && "$resolved" != "$HOME" && "$resolved" != "$ROOT" ]] || die "refusing to remove '$resolved'"
    rm -rf -- "$resolved"
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$ROOT/Resources/Info.plist"
}

require_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || die "this step requires macOS (Xcode command-line tools)"
}
