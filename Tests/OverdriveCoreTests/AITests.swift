import Foundation
import Network
import Testing
@testable import OverdriveCore

/// A tiny loopback HTTP server returning canned JSON, standing in for Ollama / LM Studio.
final class FakeAPIServer: @unchecked Sendable {
    let listener: NWListener
    let routes: [String: String]
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(routes: [String: String]) throws {
        self.routes = routes
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        listener.start(queue: .global())
        // The port is only assigned once the listener is ready.
        _ = ready.wait(timeout: .now() + 2)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [routes] data, _, _, _ in
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let body = routes[path] ?? "{}"
            let status = routes[path] == nil ? "404 Not Found" : "200 OK"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    deinit { listener.cancel() }
}

@Suite struct AITests {
    @Test func detectsRuntimesFromProcessNamesAndPaths() {
        let procs = [
            ProcessIdentity(pid: 10, name: "ollama", path: "/Applications/Ollama.app/Contents/Resources/ollama"),
            ProcessIdentity(pid: 11, name: "ollama runner", path: "/Applications/Ollama.app/Contents/Resources/ollama"),
            ProcessIdentity(pid: 12, name: "LM Studio Helper", path: "/Applications/LM Studio.app/Contents/Frameworks/LM Studio Helper.app/Contents/MacOS/LM Studio Helper"),
            ProcessIdentity(pid: 13, name: "python3.12", path: "/Users/x/ComfyUI/venv/bin/python3.12"),
            ProcessIdentity(pid: 14, name: "llama-server", path: "/opt/homebrew/bin/llama-server"),
            ProcessIdentity(pid: 15, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"),
            ProcessIdentity(pid: 16, name: "OrbStack Helper", path: "/Applications/OrbStack.app/Contents/MacOS/OrbStack Helper"),
        ]
        let found = AIRuntimeDetector.detect(procs)
        let kinds = Dictionary(uniqueKeysWithValues: found.map { ($0.kind, $0) })
        #expect(kinds[.ollama]?.pids == [10, 11])
        #expect(kinds[.ollama]?.endpoint?.port == 11434)
        #expect(kinds[.lmStudio]?.pids == [12])
        #expect(kinds[.comfyUI] != nil)
        #expect(kinds[.llamaCpp]?.endpoint?.port == 8080)
        #expect(kinds[.orbStack] != nil)
        #expect(found.count == 5)
    }

    @Test func ollamaClientParsesLoadedAndInstalledModels() async throws {
        let server = try FakeAPIServer(routes: [
            "/api/version": #"{"version":"0.12.3"}"#,
            "/api/ps": #"{"models":[{"name":"qwen3:14b","model":"qwen3:14b","size":10492738560,"size_vram":10492738560,"expires_at":"2026-10-20T14:40:00.123456-04:00","details":{"family":"qwen3","parameter_size":"14.8B","quantization_level":"Q4_K_M"}}]}"#,
            "/api/tags": #"{"models":[{"name":"qwen3:14b","size":9276000000,"modified_at":"2026-09-01T10:00:00Z","details":{"parameter_size":"14.8B","quantization_level":"Q4_K_M"}},{"name":"nomic-embed-text:latest","size":274000000,"modified_at":"2026-08-01T10:00:00Z","details":{}}]}"#,
        ])
        let client = OllamaClient(base: URL(string: "http://127.0.0.1:\(server.port)")!)
        #expect(await client.version() == "0.12.3")
        let loaded = try #require(await client.loadedModels())
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "qwen3:14b" && loaded[0].gpuSize == 10_492_738_560 && loaded[0].quantization == "Q4_K_M")
        #expect(loaded[0].expiresAt != nil)
        let installed = try #require(await client.installedModels())
        #expect(installed.map(\.name) == ["qwen3:14b", "nomic-embed-text:latest"])
        #expect(installed[0].parameters == "14.8B")
    }

    @Test func lmStudioClientSeparatesLoadedModels() async throws {
        let server = try FakeAPIServer(routes: [
            "/api/v0/models": #"{"data":[{"id":"qwen2.5-7b-instruct","object":"llm","state":"loaded","quantization":"Q4_K_M","arch":"qwen2","loaded_context_length":8192},{"id":"text-embedding-nomic","object":"embeddings","state":"not-loaded"}]}"#,
        ])
        let client = LMStudioClient(base: URL(string: "http://127.0.0.1:\(server.port)")!)
        let result = try #require(await client.models())
        #expect(result.installed.count == 2)
        #expect(result.loaded.map(\.name) == ["qwen2.5-7b-instruct"])
        #expect(result.loaded[0].contextLength == 8192)
    }

    @Test func absentServiceIsNil() async {
        let client = OllamaClient(base: URL(string: "http://127.0.0.1:1")!)
        #expect(await client.loadedModels() == nil)
        #expect(await LoopbackAPI.getJSON(URL(string: "http://example.com/api/ps")!) == nil, "never leaves loopback")
    }

    @Test func ollamaStoreFindsModelsAndOrphans() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "overdrive-ollama-\(UUID().uuidString)")
        let dir = home.appending(path: ".ollama/models")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appending(path: "manifests/registry.ollama.ai/library/llama3"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appending(path: "blobs"), withIntermediateDirectories: true)
        let manifest = #"{"schemaVersion":2,"config":{"digest":"sha256:cfg","size":100},"layers":[{"digest":"sha256:aaa","size":4000,"mediaType":"application/vnd.ollama.image.model"},{"digest":"sha256:bbb","size":50}]}"#
        try manifest.write(to: dir.appending(path: "manifests/registry.ollama.ai/library/llama3/8b"), atomically: true, encoding: .utf8)
        for (name, bytes) in [("sha256-cfg", 100), ("sha256-aaa", 4000), ("sha256-bbb", 50), ("sha256-orphan", 9000)] {
            try Data(repeating: 1, count: bytes).write(to: dir.appending(path: "blobs/\(name)"))
        }
        let (summary, orphans) = ModelStores.ollama(home: home)
        #expect(summary?.models.map(\.name) == ["llama3:8b"])
        #expect(summary?.models.first?.size == 4150)
        #expect(orphans.map(\.url.lastPathComponent) == ["sha256-orphan"])
        #expect(ModelStores.huggingFace(home: home) == nil)
    }

    @Test func headroomEstimatesFromMemory() {
        var m = MemorySnapshot()
        m.total = 24 * 1_073_741_824
        m.wired = 4 * 1_073_741_824
        m.app = 6 * 1_073_741_824
        m.compressed = 2 * 1_073_741_824
        let h = AIHeadroom.estimate(memory: m, workingSetLimit: UInt64(17.8 * 1_073_741_824))
        #expect(h.availableNow == 12 * 1_073_741_824)
        let rows = Dictionary(uniqueKeysWithValues: h.rows.map { ($0.label, $0) })
        #expect(rows["7–8B"]?.fits == true)
        #expect(rows["12–14B"]?.fits == true)
        #expect(rows["32B"]?.fits == false && rows["32B"]?.fitsAfterFreeing == false)
        #expect(rows["24B"]?.fits == false && rows["24B"]?.fitsAfterFreeing == true)
    }
}
