#!/usr/bin/env bash
# Builds build/ClaudeBuddy.app.
#   --install     also copy it into /Applications
#   --universal   build for both Apple Silicon and Intel (used for releases)
#   --zip         also write build/ClaudeBuddy.zip (for GitHub releases)
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0 UNIVERSAL=0 ZIP=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --zip) ZIP=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

ARGS=(-c release)
[[ $UNIVERSAL == 1 ]] && ARGS+=(--arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/ClaudeBuddy"
APP="build/ClaudeBuddy.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeBuddy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudeBuddy"))"

if [[ $ZIP == 1 ]]; then
  rm -f build/ClaudeBuddy.zip
  ditto -c -k --keepParent "$APP" build/ClaudeBuddy.zip
  echo "Zipped build/ClaudeBuddy.zip"
fi

if [[ $INSTALL == 1 ]]; then
  pkill -x ClaudeBuddy 2>/dev/null && sleep 0.5 || true
  rm -rf "/Applications/ClaudeBuddy.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/ClaudeBuddy.app"
fi
