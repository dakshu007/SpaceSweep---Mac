#!/usr/bin/env bash
# Packages dist/SpaceSweep.app into dist/SpaceSweep-AppleSilicon.dmg and verifies it:
# the image is checked, mounted read-only, inspected, and detached again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_macos
cd "$ROOT"

APP="$DIST_DIR/$APP_NAME.app"
DMG="$DIST_DIR/$APP_NAME-AppleSilicon.dmg"
INFO="$DIST_DIR/build-info.txt"
STAGE="$BUILD_DIR/dmg-stage"
[[ -d "$APP" ]] || die "$APP not found — run scripts/build-release.sh first"

echo "▸ Staging disk image contents"
safe_remove_generated "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "▸ Creating $DMG"
safe_remove_generated "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

echo "▸ Verifying image"
hdiutil verify "$DMG" >/dev/null
MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/spacesweep-dmg.XXXXXX")"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$DMG" >/dev/null
cleanup_mount() { hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true; }
trap cleanup_mount EXIT
echo "  contents:"; ls -1 "$MOUNT" | sed 's/^/    /'
[[ -d "$MOUNT/$APP_NAME.app" ]] || die "app missing from disk image"
[[ -L "$MOUNT/Applications" ]] || die "Applications shortcut missing from disk image"
codesign --verify --strict "$MOUNT/$APP_NAME.app" || die "app signature invalid inside disk image"
cleanup_mount
trap - EXIT

SIGNATURE="$(codesign -dv "$APP" 2>&1 | grep -E '^Signature=' | cut -d= -f2 || true)"
AUTHORITY="$(codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^Authority=' | head -1 | cut -d= -f2 || true)"
{
    echo "SpaceSweep build information"
    echo "app version:        $(plist_value CFBundleShortVersionString) ($(plist_value CFBundleVersion))"
    echo "bundle identifier:  $(plist_value CFBundleIdentifier)"
    echo "architecture:       $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
    echo "minimum macOS:      $(plist_value LSMinimumSystemVersion)"
    echo "built:              $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "built on:           macOS $(sw_vers -productVersion) ($(uname -m))"
    echo "toolchain:          $(swift --version 2>/dev/null | head -1)"
    echo "git commit:         $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "signing:            ${AUTHORITY:-${SIGNATURE:-unknown}} (hardened runtime)"
    echo "notarized:          no — personal build, not notarized"
    echo "dmg:                $(basename "$DMG")"
    echo "dmg sha256:         $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
    echo "dmg size:           $(du -h "$DMG" | cut -f1)"
} > "$INFO"

echo "✓ Disk image verified: $DMG"
cat "$INFO"
