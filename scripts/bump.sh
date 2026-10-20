#!/bin/sh
# Cuts a release: bumps the version, turns CHANGELOG's Unreleased section into a dated release,
# commits and creates an annotated tag. Pushing the tag starts the release workflow.
#
#   scripts/bump.sh 1.2.0            release 1.2.0
#   scripts/bump.sh 1.2.0 --dry-run  show what would change
#
# Afterwards: git push --follow-tags origin main
set -eu
cd "$(dirname "$0")/.."

VERSION="${1:-}"
DRY="${2:-}"
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: scripts/bump.sh <major.minor.patch> [--dry-run]" >&2; exit 2 ;;
esac

CURRENT=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)
NEXT_BUILD=$((BUILD + 1))
TODAY=$(date +%Y-%m-%d)
REPO="https://github.com/damionrashford/overdrive"

[ "$VERSION" != "$CURRENT" ] || { echo "version $VERSION is already current" >&2; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "commit or stash your changes first" >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "tag v$VERSION already exists" >&2; exit 1; }
grep -q '^## \[Unreleased\]' CHANGELOG.md || { echo "CHANGELOG.md has no Unreleased section" >&2; exit 1; }

# The Unreleased section must contain at least one entry.
ENTRIES=$(awk '/^## \[Unreleased\]/ {flag=1; next} /^## \[/ {flag=0} flag && /^- /' CHANGELOG.md | wc -l | tr -d ' ')
[ "$ENTRIES" -gt 0 ] || { echo "add release notes under ## [Unreleased] in CHANGELOG.md first" >&2; exit 1; }

echo "Releasing $VERSION (was $CURRENT), build $NEXT_BUILD, $ENTRIES changelog entries"
if [ "$DRY" = "--dry-run" ]; then
  awk '/^## \[Unreleased\]/ {flag=1; next} /^## \[/ {flag=0} flag' CHANGELOG.md
  exit 0
fi

sed -i '' -e "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$VERSION\"/" \
          -e "s/CURRENT_PROJECT_VERSION: \"$BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" packaging/homebrew-tap/Casks/overdrive.rb

# Unreleased → [VERSION] - date, with a fresh empty Unreleased above it and updated compare links.
awk -v v="$VERSION" -v d="$TODAY" -v repo="$REPO" -v prev="$CURRENT" '
  /^## \[Unreleased\]/ { print "## [Unreleased]"; print ""; print "## [" v "] - " d; next }
  /^\[Unreleased\]: / { print "[Unreleased]: " repo "/compare/v" v "...HEAD"; print "[" v "]: " repo "/compare/v" prev "...v" v; next }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

git add project.yml CHANGELOG.md packaging/homebrew-tap/Casks/overdrive.rb
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "Overdrive $VERSION"
echo "committed and tagged v$VERSION. Next: git push --follow-tags origin main"
