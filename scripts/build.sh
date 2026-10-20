#!/bin/sh
# Builds Overdrive.app into build/. Pass --install to copy it to /Applications (or ~/Applications).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Overdrive"

if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  mkdir -p build/AppIcon.iconset
  swift scripts/make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    d=$((s * 2))
    sips -z $d $d build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

APP=build/Overdrive.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Overdrive"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
  DEST=/Applications
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  pkill -x Overdrive 2>/dev/null || true
  rm -rf "$DEST/Overdrive.app"
  ditto "$APP" "$DEST/Overdrive.app"
  echo "installed $DEST/Overdrive.app"
fi
