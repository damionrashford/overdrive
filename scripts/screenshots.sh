#!/bin/sh
# Captures every page in light and dark appearance at 1440×900 points (2880×1800 px on Retina),
# the size App Store Connect accepts for Mac screenshots.
#   scripts/screenshots.sh [app bundle] [output dir]
set -eu
cd "$(dirname "$0")/.."
APP="${1:-build/Overdrive.app}"
OUT="${2:-build/screenshots}"
mkdir -p "$OUT"

cat > build/winid.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Overdrive" && (w[kCGWindowLayer as String] as? Int) == 0 {
    print(w[kCGWindowNumber as String]!)
    break
}
EOF
swiftc -O build/winid.swift -o build/winid 2>/dev/null

for appearance in dark light; do
  for page in overview cpu memory gpu disk network battery sensors processes ai cleanup apps maintenance; do
    pkill -x Overdrive 2>/dev/null || true
    sleep 0.5
    extra=""
    [ "$page" = cleanup ] && extra="--scan"
    "$APP/Contents/MacOS/Overdrive" --page "$page" --appearance "$appearance" --window 1440x900 $extra >/dev/null 2>&1 &
    sleep "${WAIT:-12}"
    id=$(build/winid)
    if [ -n "$id" ]; then
      screencapture -x -o -l "$id" "$OUT/$page-$appearance.png"
      echo "$page ($appearance)"
    else
      echo "no window for $page" >&2
    fi
  done
done
pkill -x Overdrive 2>/dev/null || true
