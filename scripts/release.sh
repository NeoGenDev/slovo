#!/bin/bash
# Builds a universal Slovo.app, packs it into build/Slovo-<version>.dmg and writes build/appcast.xml,
# Sparkle's update feed. Both files go into the GitHub release v<version>; the app reads the appcast
# of the latest release.
#
# Before a release, raise CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist:
# Sparkle compares CFBundleVersion.
#
# Without a Developer ID the app is signed ad-hoc: it runs, but macOS can't verify who made it,
# so on first launch users allow it in System Settings → Privacy & Security → Open Anyway.
# Updates are trusted through Sparkle's EdDSA signature instead, made with the private key that
# `generate_keys` keeps in the login Keychain.
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

# The appcast lists this version, the EdDSA signature of the disk image and its download link.
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
UPDATES="build/updates"
rm -rf "$UPDATES"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/NeoGenDev/slovo/releases/download/v$VERSION/" \
  -o build/appcast.xml "$UPDATES"
rm -rf "$UPDATES"
echo "Built build/appcast.xml"
