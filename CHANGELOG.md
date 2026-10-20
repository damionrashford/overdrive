# Changelog

All notable changes to Overdrive are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/): a new major for changes that alter what a cleanup action deletes, a new minor for features, a patch for fixes.

Add entries under **Unreleased** as you go; `scripts/bump.sh` turns that section into a release.

## [Unreleased]

## [1.1.0] - 2026-10-21

### Added
- Two editions from one codebase: App Store (sandboxed) and direct (Developer ID), with runtime `Capabilities` deciding what each may do.
- Sensors page: temperatures per CPU and GPU cluster, fans and system power from the SMC (direct edition).
- Battery page: health against design capacity, cycle count against its rating, charge power, voltage, adapter, Low Power Mode, Bluetooth device batteries.
- AI Workloads page: runtime detection (Ollama, LM Studio, llama.cpp, MLX, ComfyUI, Draw Things, Jan, GPT4All, OrbStack, Docker, Colima), loaded models from the Ollama and LM Studio loopback APIs with unload, model libraries on disk, orphaned Ollama blobs, unified-memory headroom estimate.
- Storage map: squarified treemap with folder drill-down and the largest files beside subfolders.
- Apps page: uninstaller that lists leftovers in Library folders before moving anything to the Trash; launchd startup items with enable/disable in the direct edition.
- Alerts for sustained CPU, memory pressure, low disk space, CPU temperature and low battery, delivered as notifications with a 15-minute cooldown.
- Menu bar styles: icon, values or live graphs for CPU, memory, network and temperature.
- History at three ranges (3 minutes, 1 hour, 24 hours) with constant memory use.
- Processes: disk I/O column (direct edition), details bar with path, parent, start time and CPU time.
- Cleanup ignore list, memory explainer sheet, system report export, Welcome and About windows, a standard Settings window.
- Opt-in weekly update check against GitHub Releases (direct edition).
- Light Mode, VoiceOver labels on gauges, charts and lists, Reduce Motion support.
- Privacy manifest, entitlements for both editions, DMG packaging, Homebrew cask template, CI and release workflows.

### Changed
- Process list works inside the App Sandbox through `proc_pidinfo`; quitting other apps is a direct-edition feature because the sandbox forbids it.
- Charts are single paths instead of Swift Charts views; long lists scroll inside fixed-height cards. Idle cost dropped from ~60% CPU and 700 MB to ~2.5% and ~150 MB.
- Storage ring and volume bar turn red under 10% free.

### Removed
- The per-process energy column: the kernel's energy accounting updates too lazily to be honest per interval.

## [1.0.0] - 2026-10-20

### Added
- First version: CPU, memory, GPU, storage and network monitoring, health score, processes with quit, junk cleanup, large-file finder, maintenance tasks, menu bar readout.

[Unreleased]: https://github.com/damionrashford/overdrive/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/damionrashford/overdrive/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/damionrashford/overdrive/releases/tag/v1.0.0
