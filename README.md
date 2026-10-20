# Overdrive

A free, open-source system monitor and cleaner for the Mac, built for the local-AI era. Native SwiftUI, no dependencies, no account, no analytics, nothing leaves your Mac.

## What it does

**Monitor.** CPU (per core, grouped by cluster), memory the way macOS measures it (pressure, app, wired, compressed, cached, swap), GPU, storage with purgeable space, network, battery health and charge power, and on the direct edition temperatures, fans and system power from the SMC. Three history ranges, a menu bar readout with live graphs, and alerts for sustained CPU, memory pressure, low disk space, heat and low battery.

**Clean.** Caches, logs, Xcode and package-manager junk, the Trash and stale downloads, measured and listed before you confirm. A treemap storage map. A large-file finder. An uninstaller that finds the files apps leave behind. A view of what launchd starts at login.

**AI workloads.** Detects Ollama, LM Studio, llama.cpp, MLX, ComfyUI, Draw Things, Jan, GPT4All and container engines; shows which models are loaded in memory and what they cost; measures model libraries on disk and finds orphaned Ollama blobs; estimates how large a model fits in unified memory right now.

**Processes.** Apps with their helpers grouped, CPU, memory, threads, and on the direct edition energy and disk I/O, with Quit and Force Quit.

## Two editions

| | Direct (download) | App Store |
|---|---|---|
| Everything above | ✓ | ✓ |
| Quit other apps, energy and disk columns | ✓ | sandbox forbids |
| Temperatures, fans, power | ✓ | sandbox forbids |
| Free memory, flush DNS, thin snapshots, rebuild Spotlight / Launch Services | ✓ | sandbox forbids |
| Cleanup folder access | automatic | you grant your home folder once |

Same code; `Capabilities` decides at runtime.

## Build

Requires macOS 15+ and Xcode 27.

```sh
brew install xcodegen
scripts/build.sh --install        # direct edition → /Applications
scripts/build.sh --appstore       # sandboxed edition → build/Overdrive-AppStore.app
swift test                        # core tests
```

Release builds (`scripts/release.sh appstore|direct`) need an Apple Developer Program membership; see [docs/app-store.md](docs/app-store.md).

## How it measures

| Metric | Source |
|---|---|
| CPU | `host_processor_info`; clusters from the IODeviceTree |
| Memory | `host_statistics64` with Activity Monitor's formula; `vm.swapusage`; kernel memory-pressure level |
| GPU | IOAccelerator `PerformanceStatistics` |
| Storage | `IOBlockStorageDriver` counters; `volumeAvailableCapacityForImportantUsage` for purgeable space |
| Network | `NET_RT_IFLIST2` 64-bit counters on physical interfaces |
| Processes | `proc_pid_rusage` (direct) or `proc_pidinfo` (sandbox); helpers grouped by `.app` bundle |
| Battery | IOPowerSources and `AppleSmartBattery` (voltage, amperage, cycles, design cycles) |
| Sensors | SMC keys through the public IOKit user client; per-chip key tables |
| AI | Loopback APIs of Ollama (`/api/ps`, `/api/tags`) and LM Studio (`/api/v0/models`); manifests and blobs in `~/.ollama/models`; the Hugging Face hub cache |

## Privacy

See [docs/privacy-policy.md](docs/privacy-policy.md). Short version: nothing is collected and nothing is sent.

## License

MIT. See [LICENSE](LICENSE).
