#!/bin/bash
# Builds a universal Slovo.app and packs it into build/Slovo-<version>.dmg for GitHub Releases.
#
# Without a Developer ID the app is signed ad-hoc: it runs, but macOS can't verify who made it,
# so on first launch users allow it in System Settings → Privacy & Security → Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/Slovo-$VERSION.dmg"
STAGING="build/dmg"

UNIVERSAL=1 CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" ./scripts/build-app.sh

# The disk image holds the app and a link to /Applications to drag it onto.
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto build/Slovo.app "$STAGING/Slovo.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Slovo $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Built $DMG"
