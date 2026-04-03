#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Audio Wave Quick Preview"
APP_BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_DIR="${1:-$HOME/Applications}"
TARGET_APP_PATH="$TARGET_DIR/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/scripts/package-app.sh"

mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_APP_PATH"
cp -R "$APP_BUNDLE_DIR" "$TARGET_APP_PATH"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_APP_PATH" >/dev/null
fi

echo "Installed app bundle:"
echo "$TARGET_APP_PATH"
