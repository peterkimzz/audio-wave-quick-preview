#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Audio Wave Quick Preview"
EXECUTABLE_NAME="AudioWaveQuickPreviewMac"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
VERSION_NAME="${VERSION_NAME:-dev}"
APP_BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ARCHIVE_NAME="AudioWaveQuickPreview-${VERSION_NAME}-macos.zip"
ARCHIVE_PATH="$ROOT_DIR/dist/$ARCHIVE_NAME"
CONTENTS_DIR="$APP_BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CACHE_ROOT="$ROOT_DIR/.build-cache"
MODULE_CACHE_DIR="$CACHE_ROOT/swift-module-cache"
CLANG_CACHE_DIR="$CACHE_ROOT/clang-module-cache"
SWIFT_HOME_DIR="$CACHE_ROOT/home"

mkdir -p "$ROOT_DIR/dist"
mkdir -p "$MODULE_CACHE_DIR" "$CLANG_CACHE_DIR" "$SWIFT_HOME_DIR"

export HOME="$SWIFT_HOME_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR"

swift build -c "$BUILD_CONFIGURATION" --product "$EXECUTABLE_NAME"

BIN_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at: $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE_DIR" "$ARCHIVE_PATH"

echo "Packaged app bundle:"
echo "$APP_BUNDLE_DIR"
echo "Packaged release archive:"
echo "$ARCHIVE_PATH"
