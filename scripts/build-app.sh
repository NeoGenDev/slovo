#!/bin/bash
# Builds the SwiftPM executable and wraps it into "build/Slovo.app".
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Slovo.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Slovo" "$APP/Contents/MacOS/Slovo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Icon Composer icon: actool turns it into Assets.car (Liquid Glass layers) plus AppIcon.icns for older systems.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "$(mktemp -d)/partial.plist" >/dev/null

# A stable signing identity keeps the Accessibility grant across rebuilds;
# ad-hoc signing ("-") changes the code hash every build and macOS forgets the grant.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [ -z "$IDENTITY" ]; then
  echo "warning: no Apple Development identity found, signing ad-hoc" >&2
  IDENTITY="-"
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP"

echo "Built $APP"
