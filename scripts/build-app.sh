#!/usr/bin/env bash
# Builds build/ClaudeBuddy.app. Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=".build/release/ClaudeBuddy"
APP="build/ClaudeBuddy.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeBuddy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Claude Buddy"' 2>/dev/null || true
  rm -rf "/Applications/ClaudeBuddy.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/ClaudeBuddy.app"
fi
