# App Store submission

Overdrive ships in two editions from one codebase: the **App Store edition** (sandboxed, config `AppStore`) and the **direct edition** (Developer ID, notarized, config `Release`). This file is the checklist and the listing copy for the App Store edition.

## What the App Store edition cannot do, and how the app handles it

| Capability | Why | What the app does instead |
|---|---|---|
| Quit or force-quit other apps | `NSRunningApplication.terminate()` returns false in the App Sandbox | Quit buttons are hidden; a note points to the app's own Quit command |
| Per-process energy and disk I/O | `proc_pid_rusage` on other processes is denied | Columns hidden; CPU, memory and threads still come from `proc_pidinfo` |
| Temperatures, fans, power | The SMC user client cannot be opened in the sandbox | Sensors page and temperature alerts hidden |
| `purge`, DNS flush, snapshot thinning, Spotlight and Launch Services rebuilds | Need root or non-sandboxed shells | Maintenance page shows only Empty Trash and explains the rest is in the direct edition |
| Reading `~/Library/Caches` etc. | Outside the container | Open panel + security-scoped bookmark; every cleanup page shows the grant card first |

Everything else (monitoring, alerts, menu bar, cleanup, large files, storage map, uninstaller with leftovers, startup items, AI workloads) is identical.

## Review checklist

- [ ] Guideline 2.4.5: sandboxed (`Config/AppStore.entitlements`), no helpers, no auto-launch without consent (login item is opt-in), no license screens, no update mechanism.
- [ ] Guideline 2.3: screenshots show the app in use; description matches the sandboxed feature set above, not the direct edition.
- [ ] Guideline 2.5.1: public APIs only. Note for reviewers: `proc_pidinfo`/`proc_pidpath` from `libproc.h` in the public SDK are used for the process list, as Activity-Monitor-style utilities on the store do.
- [ ] Guideline 5.1.1: privacy policy URL in metadata and in the app (Settings › Privacy, Help menu, Welcome window).
- [ ] Privacy nutrition label: **Data Not Collected**.
- [ ] `PrivacyInfo.xcprivacy` present (disk space, file timestamp, system boot time, user defaults).
- [ ] Age rating questionnaire: no objectionable content → 4+.
- [ ] Category: Utilities (matches `LSApplicationCategoryType`).
- [ ] Export compliance: `ITSAppUsesNonExemptEncryption` = NO.
- [ ] Icon: asset catalog `AppIcon` (1024 px source in `scripts/make-icon.swift`).
- [ ] Screenshots: 2880×1800 (window at 1440×900 points on a Retina display), light and dark, 6–8 images. `scripts/screenshots.sh` produces them.
- [ ] Version/build bumped in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
- [ ] `scripts/release.sh appstore` archives and uploads (needs an Apple Developer Program membership; Xcode must be signed in to the team).

## Listing

**Name** (≤30): Overdrive — System Monitor

**Subtitle** (≤30): CPU, memory, disk, cleanup, AI

**Promotional text**: Free and open source. No account, no analytics, nothing leaves your Mac.

**Description**:

Overdrive shows what your Mac is doing and helps you fix what slows it down.

MONITOR
• CPU with per-core load grouped by cluster, GPU utilization, memory pressure the way macOS actually measures it, storage, network and battery health
• History at three ranges (3 minutes, 1 hour, 24 hours) without growing memory use
• A menu bar readout with live graphs and a mini dashboard
• Alerts for sustained CPU load, memory pressure, low disk space and low battery

CLEAN
• Caches, logs, Xcode and package-manager junk, the Trash and stale downloads, every item listed and measured before you confirm
• A storage map that shows where the space goes, folder by folder
• Large file finder
• Uninstaller that finds the files apps leave behind in Library folders
• Startup items: see what launchd runs at login

BUILT FOR LOCAL AI
• Detects Ollama, LM Studio, llama.cpp, MLX, ComfyUI and more
• Shows which models are loaded in memory and what they cost
• Measures model libraries on disk and finds orphaned Ollama blobs
• Tells you how large a model fits in unified memory right now

PRIVATE
• No account, no analytics, no network calls (an optional public-IP lookup is off by default)
• Your own files only ever go to the Trash
• Open source under the MIT license

The App Store edition runs in the App Sandbox. Temperature sensors, quitting other apps and administrator maintenance tasks are available in the free direct edition on GitHub.

**Keywords**: system monitor,cpu,memory,gpu,disk,cleaner,uninstaller,menu bar,battery,ollama,activity,storage

**Support URL**: https://github.com/damionrashford/overdrive/issues
**Privacy policy URL**: https://github.com/damionrashford/overdrive/blob/main/docs/privacy-policy.md
**Copyright**: © 2026 Damion Rashford
**Price**: Free. No in-app purchases.

## What's New (1.1.0)

First public release.
