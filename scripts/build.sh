#!/bin/sh
# Builds Overdrive.app with Xcode.
#   scripts/build.sh                 direct edition (Release) into build/Overdrive.app
#   scripts/build.sh --appstore      App Store edition (sandboxed) into build/Overdrive-AppStore.app
#   scripts/build.sh --install       build the direct edition and copy it to /Applications (or ~/Applications)
set -eu
cd "$(dirname "$0")/.."

CONFIG=Release
OUT=build/Overdrive.app
INSTALL=no
for arg in "$@"; do
  case "$arg" in
    --appstore) CONFIG=AppStore; OUT=build/Overdrive-AppStore.app ;;
    --install) INSTALL=yes ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done

[ -d Overdrive.xcodeproj ] || xcodegen generate
xcodebuild -project Overdrive.xcodeproj -scheme Overdrive -configuration "$CONFIG" -derivedDataPath build/dd build \
  | grep -E 'error:|warning: [^M]|BUILD ' || true
rm -rf "$OUT"
ditto "build/dd/Build/Products/$CONFIG/Overdrive.app" "$OUT"
codesign --verify --strict "$OUT"
echo "built $OUT ($CONFIG)"

if [ "$INSTALL" = yes ]; then
  DEST=/Applications
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  pkill -x Overdrive 2>/dev/null || true
  rm -rf "$DEST/Overdrive.app"
  ditto "$OUT" "$DEST/Overdrive.app"
  echo "installed $DEST/Overdrive.app"
fi
