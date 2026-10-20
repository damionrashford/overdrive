import Foundation
import Observation
import OverdriveCore

/// Local AI runtimes, the models they hold in memory, model libraries on disk, and how much room
/// unified memory has for another model. Only loopback endpoints are ever contacted.
@MainActor @Observable
final class AIModel {
    var runtimes: [AIRuntime] = []
    var loaded: [LoadedModel] = []
    var installedViaAPI: [InstalledModel] = []
    var ollamaVersion: String?
    var headroom: AIHeadroom?

    var stores: [ModelStoreSummary] = []
    var orphans: [OrphanBlob] = []
    var scanningStores = false
    var storesScannedAt: Date?
    var message: String?

    @ObservationIgnored private var lastPoll: Date = .distantPast
    @ObservationIgnored private var polling = false

    var totalOnDisk: UInt64 { stores.reduce(0) { $0 + $1.totalSize } }
    var orphanBytes: UInt64 { orphans.reduce(0) { $0 + $1.size } }
    var loadedBytes: UInt64 { loaded.reduce(0) { $0 + $1.size } }

    func observe(identities: [ProcessIdentity], memory: MemorySnapshot, workingSet: UInt64) async {
        runtimes = AIRuntimeDetector.detect(identities)
        headroom = AIHeadroom.estimate(memory: memory, workingSetLimit: workingSet)
        guard !polling, Date().timeIntervalSince(lastPoll) > 10 else { return }
        polling = true
        defer { polling = false }
        lastPoll = Date()
        var newLoaded: [LoadedModel] = []
        var newInstalled: [InstalledModel] = []
        for runtime in runtimes {
            guard let endpoint = runtime.endpoint else { continue }
            switch runtime.kind {
            case .ollama:
                let client = OllamaClient(base: endpoint)
                async let version = client.version()
                async let ps = client.loadedModels()
                async let tags = client.installedModels()
                ollamaVersion = await version
                newLoaded += await ps ?? []
                newInstalled += await tags ?? []
            case .lmStudio:
                if let result = await LMStudioClient(base: endpoint).models() {
                    newLoaded += result.loaded
                    newInstalled += result.installed
                }
            default:
                break
            }
        }
        loaded = newLoaded
        installedViaAPI = newInstalled
    }

    func scanStores() async {
        guard !scanningStores else { return }
        scanningStores = true
        defer { scanningStores = false }
        let result = await Task.detached { () -> ([ModelStoreSummary], [OrphanBlob]) in
            var stores: [ModelStoreSummary] = []
            let (ollama, orphans) = ModelStores.ollama()
            if let ollama { stores.append(ollama) }
            if let lm = ModelStores.lmStudio() { stores.append(lm) }
            if let hf = ModelStores.huggingFace() { stores.append(hf) }
            return (stores, orphans)
        }.value
        stores = result.0
        orphans = result.1
        storesScannedAt = Date()
    }

    func unload(_ model: LoadedModel) async {
        guard let runtime = runtimes.first(where: { $0.kind == model.runtime }), let endpoint = runtime.endpoint,
              model.runtime == .ollama else { return }
        let ok = await OllamaClient(base: endpoint).unload(model.name)
        message = ok ? "Asked Ollama to unload \(model.name)." : "Ollama did not accept the unload request."
        lastPoll = .distantPast
    }

    /// Orphaned blobs belong to no model, so they are deleted outright (there is nothing to restore).
    func removeOrphans() async {
        let targets = orphans
        let dir = ModelStores.ollamaDirectory().appending(path: "blobs").standardizedFileURL.path
        let result = await Task.detached { () -> (UInt64, [String]) in
            var freed: UInt64 = 0
            var failures: [String] = []
            for blob in targets {
                guard blob.url.standardizedFileURL.path.hasPrefix(dir + "/") else { continue }
                do {
                    try FileManager.default.removeItem(at: blob.url)
                    freed += blob.size
                } catch {
                    failures.append(blob.url.lastPathComponent)
                }
            }
            return (freed, failures)
        }.value
        message = result.1.isEmpty ? "Removed \(Fmt.storage(result.0)) of orphaned blobs." : "Could not remove \(result.1.count) blob(s)."
        await scanStores()
        MonitorStore.shared.refreshVolumes()
    }
}
