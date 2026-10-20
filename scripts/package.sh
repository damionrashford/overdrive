#!/bin/sh
# Packages the direct edition for GitHub Releases: a drag-to-Applications DMG, a zip, and SHA256SUMS.
# Uses create-dmg (brew install create-dmg) for the Finder layout when available and plain hdiutil otherwise.
#
#   scripts/package.sh                 ad-hoc signed (what GitHub Actions ships; needs Open Anyway on first launch)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/package.sh    signed for notarization (see release.sh)
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)
APP=build/Overdrive.app
DMG="build/Overdrive-$VERSION.dmg"
ZIP="build/Overdrive-$VERSION.zip"

[ -d "$APP" ] || scripts/build.sh
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements Config/Direct.entitlements "$APP"
fi
codesign --verify --strict "$APP"

# Background: 1x and 2x joined into one multi-resolution TIFF so it stays crisp on Retina displays.
mkdir -p build/dmg-assets
swift scripts/make-dmg-background.swift build/dmg-assets/background >/dev/null
tiffutil -cathidpicheck build/dmg-assets/background.png build/dmg-assets/background@2x.png -out build/dmg-assets/background.tiff >/dev/null 2>&1

rm -f "$DMG" "$ZIP"
if command -v create-dmg >/dev/null 2>&1; then
  rm -rf build/dmg-stage && mkdir -p build/dmg-stage
  ditto "$APP" build/dmg-stage/Overdrive.app
  create-dmg \
    --volname "Overdrive" \
    --volicon "$APP/Contents/Resources/AppIcon.icns" \
    --background build/dmg-assets/background.tiff \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "Overdrive.app" 180 180 \
    --app-drop-link 480 180 \
    --hide-extension "Overdrive.app" \
    --no-internet-enable \
    "$DMG" build/dmg-stage >/dev/null
else
  rm -rf build/dmg-stage && mkdir -p build/dmg-stage
  ditto "$APP" build/dmg-stage/Overdrive.app
  ln -s /Applications build/dmg-stage/Applications
  hdiutil create -volname "Overdrive" -srcfolder build/dmg-stage -ov -format UDZO "$DMG" >/dev/null
fi
ditto -c -k --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "Overdrive-$VERSION.dmg" "Overdrive-$VERSION.zip" > SHA256SUMS)
echo "packaged:"
cat build/SHA256SUMS
