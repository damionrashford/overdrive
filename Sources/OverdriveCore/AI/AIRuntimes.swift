import Foundation

/// A local AI runtime found running on this Mac.
public struct AIRuntime: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case ollama = "Ollama"
        case lmStudio = "LM Studio"
        case llamaCpp = "llama.cpp"
        case mlx = "MLX"
        case comfyUI = "ComfyUI"
        case drawThings = "Draw Things"
        case jan = "Jan"
        case gpt4all = "GPT4All"
        case msty = "Msty"
        case diffusionBee = "DiffusionBee"
        case openWebUI = "Open WebUI"
        case orbStack = "OrbStack"
        case docker = "Docker"
        case colima = "Colima"
        case pythonML = "Python ML"
    }

    public var id: String { kind.rawValue }
    public let kind: Kind
    public let pids: [pid_t]
    /// Loopback API, when the runtime has one.
    public let endpoint: URL?

    public var name: String { kind.rawValue }
}

/// Minimal description of a process, so detection works in both editions (the App Store build only
/// has names from `KERN_PROC_ALL`, the direct build has full paths).
public struct ProcessIdentity: Sendable, Hashable {
    public let pid: pid_t
    public let name: String
    public let path: String

    public init(pid: pid_t, name: String, path: String) {
        self.pid = pid
        self.name = name
        self.path = path
    }
}

public enum AIRuntimeDetector {
    public static func detect(_ processes: [ProcessIdentity]) -> [AIRuntime] {
        var pids: [AIRuntime.Kind: [pid_t]] = [:]
        for p in processes {
            let name = p.name.lowercased()
            let path = p.path.lowercased()
            let kind: AIRuntime.Kind?
            if name == "ollama" || path.contains("/ollama.app/") || name.hasPrefix("ollama") {
                kind = .ollama
            } else if path.contains("/lm studio.app/") || name.hasPrefix("lm studio") || name == "lms" || name.hasPrefix("llmster") {
                kind = .lmStudio
            } else if name.hasPrefix("llama-server") || name.hasPrefix("llama-cli") || name.hasPrefix("llama-bench") || name == "llama-box" {
                kind = .llamaCpp
            } else if name.hasPrefix("mlx_lm") || name.hasPrefix("mlx-lm") || path.contains("/mlx_lm/") || path.contains("mlx_vlm") {
                kind = .mlx
            } else if path.contains("comfyui") || name == "comfyui" {
                kind = .comfyUI
            } else if path.contains("/draw things.app/") {
                kind = .drawThings
            } else if path.contains("/jan.app/") {
                kind = .jan
            } else if path.contains("/gpt4all.app/") || name == "gpt4all" {
                kind = .gpt4all
            } else if path.contains("/msty.app/") || name == "msty" {
                kind = .msty
            } else if path.contains("/diffusionbee.app/") {
                kind = .diffusionBee
            } else if name.hasPrefix("open-webui") || path.contains("open_webui") {
                kind = .openWebUI
            } else if name.hasPrefix("orbstack helper") || path.contains("/orbstack.app/") {
                kind = .orbStack
            } else if name.hasPrefix("com.docker.backend") || name.hasPrefix("com.docker.virt") || path.contains("/docker.app/") {
                kind = .docker
            } else if name == "limactl" || name == "colima" {
                kind = .colima
            } else if (name.hasPrefix("python") || name.hasPrefix("uv")) && (path.contains("torch") || path.contains("/transformers") || path.contains("vllm") || path.contains("diffusers")) {
                kind = .pythonML
            } else {
                kind = nil
            }
            if let kind { pids[kind, default: []].append(p.pid) }
        }
        return pids.map { kind, list in
            AIRuntime(kind: kind, pids: list.sorted(), endpoint: endpoint(for: kind))
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    static func endpoint(for kind: AIRuntime.Kind) -> URL? {
        switch kind {
        case .ollama: URL(string: "http://127.0.0.1:11434")
        case .lmStudio: URL(string: "http://127.0.0.1:1234")
        case .llamaCpp: URL(string: "http://127.0.0.1:8080")
        default: nil
        }
    }
}

// MARK: - Loopback API clients

/// A model currently loaded in a runtime's memory.
public struct LoadedModel: Sendable, Identifiable, Hashable {
    public var id: String { runtime.rawValue + "/" + name }
    public let runtime: AIRuntime.Kind
    public let name: String
    public let family: String?
    public let parameters: String?
    public let quantization: String?
    /// Bytes resident, and the part the driver placed in GPU-accessible memory.
    public let size: UInt64
    public let gpuSize: UInt64?
    public let expiresAt: Date?
    public let contextLength: Int?
}

public struct InstalledModel: Sendable, Identifiable, Hashable {
    public var id: String { store + "/" + name }
    public let store: String
    public let name: String
    public let size: UInt64
    public let modified: Date?
    public let parameters: String?
    public let quantization: String?
    public let url: URL?
}

public enum LoopbackAPI {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// GET a JSON object from a loopback service; nil when the service is not listening.
    public static func getJSON(_ url: URL) async -> [String: Any]? {
        guard url.host == "127.0.0.1" || url.host == "localhost" else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func postJSON(_ url: URL, body: [String: Any]) async -> Bool {
        guard url.host == "127.0.0.1" || url.host == "localhost" else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public struct OllamaClient: Sendable {
    public let base: URL
    public init(base: URL) { self.base = base }

    public func version() async -> String? {
        (await LoopbackAPI.getJSON(base.appending(path: "api/version")))?["version"] as? String
    }

    public func loadedModels() async -> [LoadedModel]? {
        guard let json = await LoopbackAPI.getJSON(base.appending(path: "api/ps")),
              let models = json["models"] as? [[String: Any]] else { return nil }
        return models.map { m in
            let details = m["details"] as? [String: Any]
            return LoadedModel(
                runtime: .ollama,
                name: (m["name"] as? String) ?? (m["model"] as? String) ?? "model",
                family: details?["family"] as? String,
                parameters: details?["parameter_size"] as? String,
                quantization: details?["quantization_level"] as? String,
                size: (m["size"] as? NSNumber)?.uint64Value ?? 0,
                gpuSize: (m["size_vram"] as? NSNumber)?.uint64Value,
                expiresAt: (m["expires_at"] as? String).flatMap(Self.parseDate),
                contextLength: (m["context_length"] as? NSNumber)?.intValue
            )
        }
    }

    public func installedModels() async -> [InstalledModel]? {
        guard let json = await LoopbackAPI.getJSON(base.appending(path: "api/tags")),
              let models = json["models"] as? [[String: Any]] else { return nil }
        return models.map { m in
            let details = m["details"] as? [String: Any]
            return InstalledModel(
                store: "Ollama",
                name: (m["name"] as? String) ?? (m["model"] as? String) ?? "model",
                size: (m["size"] as? NSNumber)?.uint64Value ?? 0,
                modified: (m["modified_at"] as? String).flatMap(Self.parseDate),
                parameters: details?["parameter_size"] as? String,
                quantization: details?["quantization_level"] as? String,
                url: nil
            )
        }
    }

    /// Asks Ollama to drop a model from memory now (keep_alive 0). Only ever user-initiated.
    public func unload(_ model: String) async -> Bool {
        await LoopbackAPI.postJSON(base.appending(path: "api/generate"), body: ["model": model, "keep_alive": 0])
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

public struct LMStudioClient: Sendable {
    public let base: URL
    public init(base: URL) { self.base = base }

    /// LM Studio's REST API lists every downloaded model with a loaded/not-loaded state.
    public func models() async -> (loaded: [LoadedModel], installed: [InstalledModel])? {
        guard let json = await LoopbackAPI.getJSON(base.appending(path: "api/v0/models")),
              let data = json["data"] as? [[String: Any]] else { return nil }
        var loaded: [LoadedModel] = []
        var installed: [InstalledModel] = []
        for m in data {
            let id = (m["id"] as? String) ?? "model"
            let quant = (m["quantization"] as? String)
            installed.append(InstalledModel(store: "LM Studio", name: id, size: 0, modified: nil, parameters: nil,
                                            quantization: quant, url: nil))
            if (m["state"] as? String) == "loaded" {
                loaded.append(LoadedModel(runtime: .lmStudio, name: id, family: m["arch"] as? String, parameters: nil,
                                          quantization: quant, size: 0, gpuSize: nil, expiresAt: nil,
                                          contextLength: (m["loaded_context_length"] as? NSNumber)?.intValue))
            }
        }
        return (loaded, installed)
    }
}

// MARK: - Model libraries on disk

public struct ModelStoreSummary: Sendable, Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let url: URL
    public let models: [InstalledModel]
    public var totalSize: UInt64 { models.reduce(0) { $0 + $1.size } }
}

public struct OrphanBlob: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: UInt64
}

public enum ModelStores {
    public static func ollamaDirectory(home: URL = Paths.home) -> URL {
        if let custom = ProcessInfo.processInfo.environment["OLLAMA_MODELS"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return home.appending(path: ".ollama/models")
    }

    /// Ollama's library: manifests reference layer blobs by digest; a blob no manifest references is
    /// an orphan left by an interrupted pull or a deleted model and can be removed.
    public static func ollama(home: URL = Paths.home) -> (summary: ModelStoreSummary?, orphans: [OrphanBlob]) {
        let dir = ollamaDirectory(home: home)
        let fm = FileManager.default
        let manifests = dir.appending(path: "manifests")
        let blobs = dir.appending(path: "blobs")
        guard fm.fileExists(atPath: blobs.path) else { return (nil, []) }

        var models: [InstalledModel] = []
        var referenced: Set<String> = []
        if let enumerator = fm.enumerator(at: manifests, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: []) {
            for case let file as URL in enumerator {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      let data = try? Data(contentsOf: file),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                var size: UInt64 = 0
                var layers = (json["layers"] as? [[String: Any]]) ?? []
                if let config = json["config"] as? [String: Any] { layers.append(config) }
                for layer in layers {
                    if let digest = layer["digest"] as? String { referenced.insert(digest.replacingOccurrences(of: ":", with: "-")) }
                    size += (layer["size"] as? NSNumber)?.uint64Value ?? 0
                }
                // manifests/<registry>/<namespace>/<model>/<tag>
                let parts = file.pathComponents
                guard parts.count >= 4 else { continue }
                let tag = parts[parts.count - 1], model = parts[parts.count - 2], namespace = parts[parts.count - 3]
                let name = (namespace == "library" ? model : "\(namespace)/\(model)") + ":" + tag
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                models.append(InstalledModel(store: "Ollama", name: name, size: size, modified: modified, parameters: nil,
                                             quantization: nil, url: file))
            }
        }
        var orphans: [OrphanBlob] = []
        if let files = try? fm.contentsOfDirectory(at: blobs, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []) {
            for blob in files where !referenced.contains(blob.lastPathComponent) && !blob.lastPathComponent.hasSuffix("-partial") {
                let size = UInt64((try? blob.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
                orphans.append(OrphanBlob(url: blob, size: size))
            }
            // Partial downloads older than a day are abandoned pulls.
            for blob in files where blob.lastPathComponent.hasSuffix("-partial") {
                let values = try? blob.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey])
                if let modified = values?.contentModificationDate, Date().timeIntervalSince(modified) > 86_400 {
                    orphans.append(OrphanBlob(url: blob, size: UInt64(values?.totalFileAllocatedSize ?? 0)))
                }
            }
        }
        let summary = ModelStoreSummary(name: "Ollama", url: dir, models: models.sorted { $0.size > $1.size })
        return (summary, orphans.sorted { $0.size > $1.size })
    }

    /// Hugging Face hub cache (also where MLX community models live): `models--org--name` folders.
    public static func huggingFace(home: URL = Paths.home) -> ModelStoreSummary? {
        let hub = (ProcessInfo.processInfo.environment["HF_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "hub") })
            ?? home.appending(path: ".cache/huggingface/hub")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return nil }
        var models: [InstalledModel] = []
        for folder in entries where folder.lastPathComponent.hasPrefix("models--") {
            let name = folder.lastPathComponent.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            models.append(InstalledModel(store: "Hugging Face", name: String(name), size: DirectorySize.of(folder), modified: modified,
                                         parameters: nil, quantization: nil, url: folder))
        }
        return models.isEmpty ? nil : ModelStoreSummary(name: "Hugging Face", url: hub, models: models.sorted { $0.size > $1.size })
    }

    /// LM Studio keeps `publisher/model/*.gguf` under ~/.lmstudio/models (older builds: ~/.cache/lm-studio/models).
    public static func lmStudio(home: URL = Paths.home) -> ModelStoreSummary? {
        let candidates = [home.appending(path: ".lmstudio/models"), home.appending(path: ".cache/lm-studio/models")]
        guard let dir = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        var models: [InstalledModel] = []
        let publishers = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for publisher in publishers {
            let items = (try? FileManager.default.contentsOfDirectory(at: publisher, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for model in items {
                let modified = (try? model.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                models.append(InstalledModel(store: "LM Studio", name: "\(publisher.lastPathComponent)/\(model.lastPathComponent)",
                                             size: DirectorySize.of(model), modified: modified, parameters: nil, quantization: nil, url: model))
            }
        }
        return models.isEmpty ? nil : ModelStoreSummary(name: "LM Studio", url: dir, models: models.sorted { $0.size > $1.size })
    }
}

// MARK: - Headroom

/// How much of unified memory a local model can take right now, and which common sizes fit.
public struct AIHeadroom: Sendable {
    public struct Row: Sendable, Identifiable, Hashable {
        public var id: String { label }
        public let label: String
        public let bytes: UInt64
        public let fits: Bool
        public let fitsAfterFreeing: Bool
    }

    public let availableNow: UInt64
    public let reclaimable: UInt64
    public let workingSetLimit: UInt64
    public let rows: [Row]

    /// Bytes a model needs at 4-bit quantization: ~0.56 bytes per parameter plus a 1 GB allowance for
    /// the KV cache and runtime. Labels follow the parameter counts people actually download.
    public static let sizes: [(label: String, parameters: Double)] = [
        ("3B", 3e9), ("7–8B", 8e9), ("12–14B", 14e9), ("24B", 24e9), ("32B", 32e9), ("70B", 70e9), ("120B", 120e9),
    ]

    public static func estimate(memory: MemorySnapshot, workingSetLimit: UInt64) -> AIHeadroom {
        // Wired, app and compressed pages are busy; file cache can be evicted on demand.
        let busy = memory.wired + memory.app + memory.compressed
        let free = memory.total > busy ? memory.total - busy : 0
        let limit = workingSetLimit > 0 ? workingSetLimit : memory.total
        let available = min(free, limit)
        // What quitting the biggest consumers could give back: app memory is the only part a person controls.
        let afterFreeing = min(limit, free + memory.app / 2)
        let rows = sizes.map { entry -> Row in
            let bytes = UInt64(entry.parameters * 0.56) + 1_073_741_824
            return Row(label: entry.label, bytes: bytes, fits: bytes <= available, fitsAfterFreeing: bytes <= afterFreeing)
        }
        return AIHeadroom(availableNow: available, reclaimable: memory.app / 2, workingSetLimit: limit, rows: rows)
    }
}
