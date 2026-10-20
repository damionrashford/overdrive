#!/bin/sh
# Installs or updates Overdrive from GitHub Releases.
#
#   curl -fsSL https://raw.githubusercontent.com/damionrashford/overdrive/main/install.sh | sh
#
# What it does, in order: checks this is an Apple silicon Mac on macOS 15 or later, downloads the
# release zip and its SHA256SUMS, verifies the checksum, copies Overdrive.app into /Applications
# (or ~/Applications when /Applications is not writable), removes the quarantine flag so macOS does
# not block the first launch, verifies the code signature, and opens the app. No sudo, no telemetry.
#
#   OVERDRIVE_VERSION=1.1.0 sh install.sh      install a specific version
#   sh install.sh --uninstall                   remove the app and its preferences
set -eu

REPO="damionrashford/overdrive"
APP_NAME="Overdrive"
BUNDLE_ID="com.damionrashford.overdrive"
# Overridable for testing against a local build: OVERDRIVE_ASSET_BASE=file:///path/to/build
ASSET_BASE="${OVERDRIVE_ASSET_BASE:-}"

say() { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  pkill -x "${APP_NAME}" 2>/dev/null || true
  removed=0
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/${APP_NAME}.app" ]; then
      rm -rf "$dir/${APP_NAME}.app" && say "removed $dir/${APP_NAME}.app" && removed=1
    fi
  done
  rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  rm -rf "$HOME/Library/Caches/$BUNDLE_ID"
  [ "$removed" = 1 ] || say "${APP_NAME} was not installed"
  say "preferences removed. If 'Open at login' was on, remove Overdrive under System Settings › General › Login Items."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || fail "this installs a macOS app"
[ "$(uname -m)" = "arm64" ] || fail "Overdrive needs an Apple silicon Mac (this one reports $(uname -m))"
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || fail "Overdrive needs macOS 15 or later (this Mac runs $(sw_vers -productVersion))"
command -v curl >/dev/null || fail "curl is required"

# Resolve the version and where the assets live.
if [ -n "$ASSET_BASE" ]; then
  VERSION="${OVERDRIVE_VERSION:?set OVERDRIVE_VERSION with OVERDRIVE_ASSET_BASE}"
elif [ -n "${OVERDRIVE_VERSION:-}" ]; then
  VERSION="$OVERDRIVE_VERSION"
  ASSET_BASE="https://github.com/$REPO/releases/download/v${VERSION}"
else
  say "Looking up the latest release..."
  VERSION=$(curl -fsSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)
  [ -n "${VERSION}" ] || fail "could not read the latest release from GitHub"
  ASSET_BASE="https://github.com/$REPO/releases/download/v${VERSION}"
fi
ZIP="${APP_NAME}-${VERSION}.zip"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/overdrive-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

say "Downloading ${APP_NAME} ${VERSION}..."
curl -fsSL --retry 3 -o "$TMP/$ZIP" "$ASSET_BASE/$ZIP" || fail "download failed: $ASSET_BASE/$ZIP"
curl -fsSL --retry 3 -o "$TMP/SHA256SUMS" "$ASSET_BASE/SHA256SUMS" || fail "checksum file missing from the release"

# Integrity: the archive must match the checksum published with the same release.
expected=$(awk -v f="$ZIP" '$2 == f {print $1}' "$TMP/SHA256SUMS")
[ -n "$expected" ] || fail "no checksum for $ZIP in SHA256SUMS"
actual=$(shasum -a 256 "$TMP/$ZIP" | awk '{print $1}')
[ "$actual" = "$expected" ] || fail "checksum mismatch for $ZIP (expected $expected, got $actual). Not installing."
say "Checksum verified."

ditto -x -k "$TMP/$ZIP" "$TMP/extract" || fail "could not extract $ZIP"
[ -d "$TMP/extract/${APP_NAME}.app" ] || fail "archive does not contain ${APP_NAME}.app"

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  say "Quitting the running copy..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || pkill -x "${APP_NAME}" || true
  sleep 1
fi
rm -rf "$DEST/${APP_NAME}.app"
ditto "$TMP/extract/${APP_NAME}.app" "$DEST/${APP_NAME}.app"

# The download was verified above; clearing quarantine is what lets macOS open an app that is not
# notarized by Apple without the "could not verify" dialog.
xattr -dr com.apple.quarantine "$DEST/${APP_NAME}.app" 2>/dev/null || true
codesign --verify --strict "$DEST/${APP_NAME}.app" || fail "the installed app failed signature verification"

say "Installed $DEST/${APP_NAME}.app (${VERSION})."
open "$DEST/${APP_NAME}.app"
say "Overdrive is open. Update later by running this script again; remove with: sh install.sh --uninstall"
