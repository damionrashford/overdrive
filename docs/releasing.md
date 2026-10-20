# Releasing

One version number, three outputs: a GitHub release (DMG, zip, checksums), the Homebrew tap, and later the App Store build. Everything keys off `MARKETING_VERSION` in `project.yml` and a `vX.Y.Z` tag.

## Versioning

Semantic versioning. Bump the **major** version for anything that changes what a cleanup, uninstall or maintenance action deletes or touches. **Minor** for features and new pages. **Patch** for fixes. `CURRENT_PROJECT_VERSION` (the build number) increases by one on every release; App Store Connect requires it to be unique.

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Every pull request that changes behavior adds a line under `## [Unreleased]` in one of `### Added`, `### Changed`, `### Fixed`, `### Removed` or `### Security`. Write it for a person reading the release page, not a commit log: what they can now do or what no longer goes wrong.

## Cutting a release

```sh
scripts/bump.sh 1.2.0 --dry-run   # shows the notes that will ship
scripts/bump.sh 1.2.0             # bumps project.yml and the cask, dates the changelog, commits, tags v1.2.0
git push --follow-tags origin main
```

Pushing the tag runs `.github/workflows/release.yml`, which:

1. Checks the tag matches `MARKETING_VERSION`.
2. Runs the core tests, builds the direct edition, packages the DMG and zip (`scripts/package.sh`) and writes `SHA256SUMS`.
3. Publishes a GitHub Release whose notes are the changelog section for that version, plus install instructions and checksums.
4. If the `TAP_TOKEN` secret exists, updates `Casks/overdrive.rb` in `damionrashford/homebrew-tap` with the new version and checksum.

Then verify on a clean Mac (or a fresh user account): `brew upgrade --cask overdrive`, open the app, confirm About shows the new version, confirm Help › Check for Updates reports it as current.

## Signing

Releases built by GitHub Actions are ad-hoc signed because the repository has no Apple certificates. They run after the person allows them once (see [install.md](install.md)). To ship notarized builds, add a Developer ID certificate and an App Store Connect API key to the release machine and use `scripts/release.sh direct`; the DMG from `scripts/package.sh` can also be signed and notarized by setting `SIGN_IDENTITY` before packaging and submitting with `notarytool`. Details in [app-store.md](app-store.md).

## Hotfixes

Branch from the tag (`git checkout -b hotfix/1.2.1 v1.2.0`), fix, add a `### Fixed` entry under Unreleased, `scripts/bump.sh 1.2.1`, push the tag, then merge the branch back into `main`.

## What never goes in the repository

Build products (`build/`, `.build/`), the generated `Overdrive.xcodeproj` (regenerate with `xcodegen generate` or `scripts/build.sh`), disk images and archives, certificates, provisioning profiles, API keys, export option plists with team details, scratch test homes and screenshots other than the curated set in `docs/images`. `.gitignore` enforces this; `git status --ignored` shows what it is keeping out.
