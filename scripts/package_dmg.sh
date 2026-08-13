#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg"
DMG_PATH="$DIST_DIR/Sidetop-1.0.0-universal.dmg"

"$PROJECT_DIR/scripts/build_release.sh"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$BUILD_DIR/Sidetop.app" "$STAGING_DIR/Sidetop.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create -volname "Sidetop" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "Created $DMG_PATH"
shasum -a 256 "$DMG_PATH"
