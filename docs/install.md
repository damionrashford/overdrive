# Installing Overdrive

Overdrive needs macOS 15 or later on Apple silicon. There are four ways to install the direct edition; the App Store edition will be listed separately when it ships.

## 1. One-line installer

```sh
curl -fsSL https://raw.githubusercontent.com/damionrashford/overdrive/main/install.sh | sh
```

The script is [in the repository](../install.sh), so read it first if you like. It downloads the latest release zip and its `SHA256SUMS`, refuses to continue if the checksum does not match, copies Overdrive.app to `/Applications` (or `~/Applications` if that is not writable), clears the quarantine flag so macOS does not block the first launch, verifies the code signature and opens the app. It never uses `sudo`. Run it again to update; `sh install.sh --uninstall` removes the app and its preferences. `OVERDRIVE_VERSION=1.1.0` pins a version.

## 2. Homebrew

```sh
brew tap damionrashford/tap
brew install --cask --no-quarantine overdrive
```

`--no-quarantine` matters: the app is signed but not yet notarized by Apple, and without the flag macOS asks you to allow it once (see [First launch](#first-launch)). Updating and removing:

```sh
brew upgrade --cask overdrive
brew uninstall --cask --zap overdrive      # --zap also removes preferences
```

## 3. Download

1. Get `Overdrive-<version>.dmg` from the [latest release](https://github.com/damionrashford/overdrive/releases/latest).
2. Open it and drag **Overdrive** onto **Applications**.
3. Eject the disk image and open Overdrive from Applications or Spotlight.

To verify the download, compare its checksum with `SHA256SUMS` on the release page:

```sh
shasum -a 256 ~/Downloads/Overdrive-*.dmg
```

A zip of the app is also attached for people who prefer it.

## 4. Build from source

Requires Xcode 27 (or the current stable Xcode) and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/damionrashford/overdrive.git
cd overdrive
brew install xcodegen
scripts/build.sh --install        # builds the direct edition and copies it to /Applications
```

`scripts/build.sh --appstore` builds the sandboxed edition into `build/` if you want to see how it behaves. The Xcode project is generated on the fly from `project.yml`; `xcodegen generate && open Overdrive.xcodeproj` opens it in Xcode.

## First launch

Overdrive is code-signed, but not notarized by Apple yet (notarization needs a paid Apple Developer membership; it is on the roadmap). On macOS 15 and later the first launch of a downloaded, un-notarized app is blocked with *"Apple could not verify Overdrive is free of malware"*. To allow it once:

1. Click **Done** on that dialog.
2. Open **System Settings › Privacy & Security**, scroll to **Security**.
3. Next to *"Overdrive was blocked to protect your Mac"*, click **Open Anyway**, then confirm.

macOS remembers the decision. The equivalent from the Terminal, which also skips the dialog, is:

```sh
xattr -dr com.apple.quarantine /Applications/Overdrive.app
```

If macOS says the app is *"damaged and can't be opened"*, the download was quarantined and the app's signature does not match what macOS expected; the `xattr` command above fixes it, or install through Homebrew with `--no-quarantine`.

### What Overdrive asks for

| Prompt | When | Why |
|---|---|---|
| Access to Downloads, Desktop or Documents | the first cleanup, large-file or storage-map scan that reaches those folders | measuring sizes; nothing is changed until you confirm |
| Control Finder | running **Empty Trash** in Maintenance | Finder empties every volume's Trash correctly |
| Notifications | when you turn on alerts | CPU, memory, disk and heat alerts |
| Administrator password | the Admin-marked maintenance tasks | macOS runs `purge`, `tmutil`, `mdutil` or the DNS flush; Overdrive never sees the password |

Overdrive never asks for Full Disk Access and never installs a helper, launch agent or daemon. "Open at login" is off until you turn it on.

## Updating

Homebrew: `brew upgrade --cask overdrive`. Downloads: Settings › General › **Check for updates weekly** asks GitHub for the latest release (off by default), or use Help › **Check for Updates…**. Replace the app in Applications with the new one; preferences carry over.

## Uninstalling

Quit Overdrive, move `/Applications/Overdrive.app` to the Trash, and optionally remove:

```
~/Library/Preferences/com.damionrashford.overdrive.plist
~/Library/Caches/com.damionrashford.overdrive
```

If you enabled "Open at login", turn it off in Settings first (or remove Overdrive under System Settings › General › Login Items).

## Troubleshooting

**The menu bar item is missing.** macOS hides menu bar items when the bar is full. System Settings › Menu Bar (or Control Center on older systems) controls which items show; the window still works without it.

**Temperatures, fans or the Sensors page are missing.** Sensors are read from the SMC, which the App Store sandbox does not allow and which virtual machines do not expose. The direct edition on real Apple silicon shows them.

**Some processes are missing.** Processes owned by other users (root, `_windowserver`) need administrator rights to inspect and are not listed; they still count toward the totals.

**Cleanup found less than expected.** Only folders Overdrive can read are measured. `~/Library/Caches` entries that belong to system apps are protected by macOS and are listed but never preselected.

**Logs.** Overdrive writes no log files. For a bug report use Help › **Copy System Report**.
