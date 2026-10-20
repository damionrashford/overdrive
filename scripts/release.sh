#!/bin/sh
# Produces distributable builds. Needs an Apple Developer Program membership for the certificates.
#
#   scripts/release.sh appstore      archive the sandboxed edition and upload it to App Store Connect
#   scripts/release.sh direct        archive the direct edition, notarize it and write build/Overdrive-<version>.dmg
#
# Prerequisites (once):
#   - Xcode signed in to the team (Xcode › Settings › Accounts) so automatic signing can fetch
#     "Apple Distribution" / "Developer ID Application" certificates.
#   - For notarization: xcrun notarytool store-credentials overdrive --apple-id <id> --team-id <team> --password <app-specific>
set -eu
cd "$(dirname "$0")/.."

TEAM_ID="${OVERDRIVE_TEAM_ID:-9MH63W8M2F}"
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)
MODE="${1:-}"
[ -d Overdrive.xcodeproj ] || xcodegen generate

case "$MODE" in
  appstore)
    ARCHIVE=build/Overdrive-AppStore.xcarchive
    rm -rf "$ARCHIVE"
    xcodebuild archive -project Overdrive.xcodeproj -scheme "Overdrive App Store" -configuration AppStore \
      -archivePath "$ARCHIVE" -allowProvisioningUpdates \
      CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Distribution" DEVELOPMENT_TEAM="$TEAM_ID" \
      | grep -E 'error:|ARCHIVE ' || true
    cat > build/ExportOptions-AppStore.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
EOF
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions-AppStore.plist \
      -exportPath build/export-appstore -allowProvisioningUpdates
    echo "uploaded Overdrive $VERSION to App Store Connect"
    ;;
  direct)
    ARCHIVE=build/Overdrive-Direct.xcarchive
    rm -rf "$ARCHIVE" build/export-direct
    xcodebuild archive -project Overdrive.xcodeproj -scheme Overdrive -configuration Release \
      -archivePath "$ARCHIVE" -allowProvisioningUpdates \
      CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
      | grep -E 'error:|ARCHIVE ' || true
    cat > build/ExportOptions-Direct.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions-Direct.plist \
      -exportPath build/export-direct -allowProvisioningUpdates
    APP=build/export-direct/Overdrive.app
    DMG="build/Overdrive-$VERSION.dmg"
    rm -rf build/dmg "$DMG"
    mkdir -p build/dmg
    ditto "$APP" build/dmg/Overdrive.app
    ln -s /Applications build/dmg/Applications
    hdiutil create -volname "Overdrive" -srcfolder build/dmg -ov -format UDZO "$DMG" >/dev/null
    codesign --sign "Developer ID Application" --timestamp "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile overdrive --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    echo "notarized $DMG"
    ;;
  *)
    echo "usage: scripts/release.sh appstore|direct" >&2
    exit 2
    ;;
esac
