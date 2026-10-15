#!/usr/bin/env bash
# Builds the Release SpaceSweep.app for Apple silicon (arm64) into dist/.
#
# Signing: ad-hoc with the hardened runtime by default (personal build).
# Set SPACESWEEP_SIGN_IDENTITY="Developer ID Application: …" to sign with a real identity.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_macos
cd "$ROOT"

ARCH="${ARCH:-arm64}"
IDENTITY="${SPACESWEEP_SIGN_IDENTITY:--}"
VERSION="$(plist_value CFBundleShortVersionString)"

echo "▸ Building $APP_NAME $VERSION (release, $ARCH)"
swift build -c release --arch "$ARCH" --product "$APP_NAME"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"
[[ -x "$BIN_DIR/$APP_NAME" ]] || die "executable not found at $BIN_DIR/$APP_NAME"

APP="$BUILD_DIR/$APP_NAME.app"
safe_remove_generated "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signing ($([[ "$IDENTITY" == "-" ]] && echo "ad-hoc" || echo "$IDENTITY"), hardened runtime)"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
[[ "$ARCHS" == *"$ARCH"* ]] || die "expected $ARCH binary, got: $ARCHS"

mkdir -p "$DIST_DIR"
safe_remove_generated "$DIST_DIR/$APP_NAME.app"
ditto "$APP" "$DIST_DIR/$APP_NAME.app"
echo "✓ Built $DIST_DIR/$APP_NAME.app ($ARCHS)"
