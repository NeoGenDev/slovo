#!/bin/bash
# Builds the SwiftPM executable and wraps it into "build/Slovo.app".
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Slovo.app"

# UNIVERSAL=1 builds for both Apple silicon and Intel, as releases need.
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Slovo" "$APP/Contents/MacOS/Slovo"
# Sparkle for updates; the executable finds it through its @executable_path/../Frameworks rpath.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
# Hardened runtime needs the app and Sparkle signed by the same team. Ad-hoc signatures have no
# team, so release builds (ad-hoc, see release.sh) go without it; it only matters for notarization.
RUNTIME=(--options runtime)
if [ "$IDENTITY" = "-" ]; then RUNTIME=(); fi
sign() { codesign --force ${RUNTIME[@]+"${RUNTIME[@]}"} --sign "$IDENTITY" "$@"; }

# Sparkle's helpers first, inside out, as its documentation describes; then the app around them.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP"

echo "Built $APP"
