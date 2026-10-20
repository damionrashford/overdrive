# Architecture

Overdrive is one SwiftUI app built from two targets. `OverdriveCore` reads the system and changes files; it has no views and is unit-tested. `Overdrive` is the app: observable state, components, pages and windows.

```
Sources/
├── OverdriveCore/
│   ├── Capabilities.swift        what this edition may do (sandbox detection)
│   ├── Format.swift              number formatting, Paths.home
│   ├── Metrics/                  one sampler per subsystem, all delta-based
│   │   ├── CPUSampler            host_processor_info; clusters from the IODeviceTree
│   │   ├── MemorySampler         host_statistics64, vm.swapusage, memorystatus level
│   │   ├── GPUSampler            IOAccelerator PerformanceStatistics
│   │   ├── DiskSampler           IOBlockStorageDriver counters, mounted volumes
│   │   ├── NetworkSampler        NET_RT_IFLIST2 64-bit counters, SCNetworkInterface names
│   │   ├── PowerSampler          IOPowerSources, AppleSmartBattery, Bluetooth batteries
│   │   ├── ProcessSampler        proc_pid_rusage (direct) or KERN_PROC_ALL + proc_pidinfo (sandbox)
│   │   ├── SMC + SensorSampler   AppleSMC user client, per-chip key tables
│   │   └── SamplerEngine         actor that owns the samplers and returns one SystemSample
│   ├── Cleanup/                  catalog, engine with the safety guard, size scanner,
│   │                             large-file scanner, space tree, uninstaller, startup items
│   ├── Maintenance/              fixed command catalog, shell and AppleScript runners
│   └── AI/                       runtime detection, Ollama / LM Studio clients, model stores, headroom
└── Overdrive/
    ├── Model/                    MonitorStore (the single source of truth), feature models, settings, alerts
    ├── Components/               Theme (adaptive tokens), charts, gauges, controls, treemap
    ├── Pages/                    one file per sidebar page, plus SettingsView
    └── App/                      entry point, root view, menu bar, auxiliary windows, self-test, diagnostics
```

## Data flow

`MonitorStore.start()` runs a loop: every `refreshInterval` seconds it awaits `SamplerEngine.sample()` on the engine's actor, assigns the snapshot to its observable properties, appends to each `History`, evaluates alert rules and lets `AIModel` observe the process list. Views read the store through the SwiftUI environment and re-render only what changed.

Samplers are stateful (they keep the previous counters) and never touch the main thread. Everything that walks the file system (`DirectorySize`, `LargeFileScanner`, `SpaceScanner`, `AppInventory`) runs in `Task.detached` and reports progress back to the main actor.

## History without growth

`History` keeps three fixed ring buffers per metric: every sample for ~3 minutes, 20-second averages for an hour, 5-minute averages for a day. Memory stays constant however long the app runs, and the chart range picker just selects a buffer.

## Rendering budget

A monitor that costs more than it measures is a bug. The rules that keep Overdrive at ~2–3% CPU:

- No per-sample animations. Ring gauges sweep in once on appearance; values then update without animation. (Animating every sample at 120 Hz re-lays out the window and cost ~15% CPU.)
- Charts are single `Path` shapes rasterized with `drawingGroup`, not per-point views.
- Long lists scroll inside fixed-height cards; a card as tall as 500 rows gets a backing layer of half a gigabyte.
- Icons are cached by kind as 64-pixel bitmaps; hundreds of bare executables share one.

## Editions

`Capabilities.current` detects the App Sandbox at launch (`APP_SANDBOX_CONTAINER_ID`). Everything that differs between editions reads from it: process quitting, disk I/O columns, sensors, shell-based maintenance, and the home-folder grant flow (`AccessManager`, security-scoped bookmarks). The same binary runs as either edition; only the entitlements differ (`Config/`).

## Safety

Every destructive path goes through one of a few functions with tests on throwaway folders: `CleanupEngine.clean` (guarded by `isSafeTarget`, which refuses anything outside the home folder, the protected top-level folders, and symlinks leading out), `FileManager.trashItem` for the person's own files, `AppInventory.uninstall` (Trash only), and `AIModel.removeOrphans` (only inside Ollama's blob directory). Administrator tasks are a fixed catalog of command strings; nothing is built from user input.

## Testing

- `swift test`: core suites on real system data plus fixture folders (cleanup safety, scanners, uninstaller, startup items, AI parsing against a fake loopback server, version comparison). Hardware-dependent tests skip on machines without an SMC.
- `Overdrive --e2e` with `OVERDRIVE_HOME` set to a fixture folder: drives the real models the buttons call, end to end, and logs PASS/FAIL per step. Runs in both editions (the sandboxed one with the fixture inside its container).
- `Overdrive --dump`: raw samples to compare against `vm_stat`, `top`, `iostat` and `netstat`.
