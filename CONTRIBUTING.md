# Contributing

Overdrive is a native SwiftUI app with no third-party dependencies. Pull requests are welcome.

## Layout

| Path | What |
|---|---|
| `Sources/OverdriveCore` | Everything that reads the system or changes files: samplers (`Metrics/`), cleanup engines (`Cleanup/`), maintenance tasks (`Maintenance/`), local AI runtimes (`AI/`). No AppKit views. Unit-tested. |
| `Sources/Overdrive` | The app: `Model/` (observable state), `Components/` (theme and reusable views), `Pages/`, `App/` (entry point, windows, menu bar, self-test). |
| `Tests/OverdriveCoreTests` | swift-testing suites. Anything that touches files runs on a throwaway folder. |
| `Config/` | Entitlements for the two editions. |
| `scripts/` | Build, release, icon and screenshot scripts. |

## Working on it

```sh
swift test                              # core tests
scripts/build.sh --install              # direct edition into /Applications
scripts/build.sh --appstore             # sandboxed edition into build/
build/Overdrive.app/Contents/MacOS/Overdrive --dump       # raw metrics to compare with vm_stat / top / netstat
OVERDRIVE_HOME=/tmp/fake build/Overdrive.app/Contents/MacOS/Overdrive --e2e   # end-to-end self test on a scratch home
```

`xcodegen generate` rebuilds `Overdrive.xcodeproj` from `project.yml`; edit the YAML, not the project.

Releases: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, add a section to `CHANGELOG.md`, tag `vX.Y.Z` and push the tag. The release workflow builds, packages (`scripts/package.sh`) and publishes the DMG, zip and checksums, and updates the Homebrew tap when the `TAP_TOKEN` secret is present. `scripts/release.sh` is the notarized / App Store path for when a Developer ID exists.

## Rules that keep the app honest

- Never delete a person's own files: large files, downloads, app leftovers and startup items go to the Trash.
- Cleanup targets stay inside the home folder (`CleanupEngine.isSafeTarget`); add a test when you add a location.
- No network calls except loopback AI runtimes and the opt-in public IP lookup.
- No per-sample animations. A monitor that costs 15% CPU is a bug.
- Every capability that differs between editions goes through `Capabilities` so the sandboxed build degrades deliberately.
- Keep the UI free of filler: no explanatory cards that a tooltip could replace, no decorative effects that cost frames.
