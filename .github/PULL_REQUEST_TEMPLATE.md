## What this changes

<!-- One paragraph. Link the issue if there is one. -->

## How it was verified

- [ ] `swift test` passes
- [ ] Both editions build (`scripts/build.sh` and `scripts/build.sh --appstore`)
- [ ] If it touches files on disk: covered by a test on a throwaway folder, and `CleanupEngine.isSafeTarget` still guards it
- [ ] If it touches the UI: checked in Light and Dark Mode, and Overdrive's own CPU stays under ~3% at idle (Settings › General shows it)

## Screenshots

<!-- For UI changes, before/after at 1440×900. -->
