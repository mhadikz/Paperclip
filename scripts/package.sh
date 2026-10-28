#!/bin/bash
# Produces a distributable zip (and a DMG when `create-dmg`-free hdiutil is enough) from build/.
#
#   scripts/package.sh            → build/dist/Paperclip-<version>.zip + .dmg
#
# For public distribution sign with a Developer ID and notarize:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build.sh --release --no-install
#   scripts/package.sh
#   xcrun notarytool submit build/dist/Paperclip-<version>.zip --keychain-profile "AC_PASSWORD" --wait
#   xcrun stapler staple build/Paperclip.app && scripts/package.sh   # re-package the stapled app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Paperclip.app"
DIST="$ROOT/build/dist"
[ -d "$APP" ] || { echo "Build first: scripts/build.sh --release --no-install" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NAME="Paperclip-$VERSION"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "→ Zipping"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"

echo "→ Building DMG"
STAGE="$ROOT/build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Paperclip" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DIST/$NAME.dmg"
rm -rf "$STAGE"

echo "→ Checksums"
(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" | tee SHA256SUMS.txt)
echo "→ Artifacts in $DIST"
