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

UNIVERSAL=1 CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" ./scripts/build-app.sh

# The disk image window, laid out by dmgbuild (scripts/dmg-settings.py): it writes Finder's
# .DS_Store itself, so no AppleScript driving Finder. Installed once into its own venv in .build.
DMGBUILD=".build/dmgbuild/bin/dmgbuild"
if [ ! -x "$DMGBUILD" ]; then
  python3 -m venv .build/dmgbuild
  .build/dmgbuild/bin/pip install --quiet --disable-pip-version-check "dmgbuild==1.6.5"
fi
rm -f "$DMG"
"$DMGBUILD" -s scripts/dmg-settings.py \
  -D app=build/Slovo.app -D icon=build/Slovo.app/Contents/Resources/AppIcon.icns \
  "Slovo $VERSION" "$DMG" >/dev/null
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
