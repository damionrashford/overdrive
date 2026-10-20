# Overdrive

A native macOS app that monitors and optimizes your Mac: CPU, memory, GPU, storage, network, processes, junk cleanup and one-click maintenance, with a live menu bar dashboard. Pure SwiftUI, no dependencies, no network access, nothing collected.

## Build and install

```sh
./scripts/build.sh --install     # builds build/Overdrive.app and copies it to /Applications
swift test                       # core unit tests (metrics, cleanup safety, shell)
```

Requires macOS 15+ and Xcode 27 (Swift 6). The app is ad-hoc signed, so the first launch may need right-click → Open.

## What it does

| Page | Source of truth |
|---|---|
| CPU | `host_processor_info` per core; clusters from the IODeviceTree (`Super`, `Performance`, `Efficiency`) |
| Memory | `host_statistics64` with Activity Monitor's formula (app + wired + compressed), `vm.swapusage`, kernel pressure level |
| GPU | IOAccelerator `PerformanceStatistics` (device / renderer / tiler utilization, driver memory) |
| Storage | `IOBlockStorageDriver` byte counters; volume capacity including purgeable space |
| Network | `NET_RT_IFLIST2` 64-bit counters on physical interfaces (VPN tunnels are not double-counted) |
| Processes | `proc_pid_rusage` footprint and CPU time for processes you own, helpers grouped under their app |
| Cleanup | App caches, logs, Xcode and package-manager junk, Trash, stale downloads. Nothing is deleted until reviewed; Apple caches and slow-to-rebuild caches are never preselected |
| Maintenance | purge, DNS flush, snapshot thinning, Quick Look reset, Launch Services rebuild, Spotlight reindex, simulators, Homebrew cleanup. Admin tasks go through the standard macOS password dialog |

## Safety

- Cleanup only ever touches paths inside your home folder and refuses `~`, `~/Documents`, `~/Desktop`, `~/Library` and the like as whole targets. Symlinked cache folders that point outside your home are refused.
- Your own files (large files, downloads) are moved to the Trash, never deleted.
- Quitting a process always asks first.

## Development

```sh
Overdrive --dump                 # print one sample of every metric to compare with vm_stat / top / netstat
Overdrive --page cpu             # open on a page
OVERDRIVE_HOME=/tmp/fakehome Overdrive --e2e   # end-to-end self test against a scratch home folder
```
