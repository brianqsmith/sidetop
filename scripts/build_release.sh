#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/Sidetop.app"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

build_arch() {
    local arch="$1"
    env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
        SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
        swift build --disable-sandbox -c release --arch "$arch" \
        --build-path "$PROJECT_DIR/.build/$arch"
}

build_arch arm64
build_arch x86_64

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

lipo -create \
    "$PROJECT_DIR/.build/arm64/arm64-apple-macosx/release/Sidetop" \
    "$PROJECT_DIR/.build/x86_64/x86_64-apple-macosx/release/Sidetop" \
    -output "$APP_DIR/Contents/MacOS/Sidetop"

cp "$PROJECT_DIR/Assets/Sidetop.icns" "$APP_DIR/Contents/Resources/Sidetop.icns"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/Sidetop"

echo "Built $APP_DIR"
lipo -archs "$APP_DIR/Contents/MacOS/Sidetop"
