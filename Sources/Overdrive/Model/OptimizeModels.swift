import AppKit
import Observation
import OverdriveCore
import SwiftUI

@MainActor @Observable
final class CleanupModel {
    enum Phase { case idle, scanning, ready, cleaning, done }

    struct Entry: Identifiable {
        let item: CleanupItem
        let displayName: String
        var size: UInt64?
        var selected: Bool
        var id: String { item.id }
    }

    struct Group: Identifiable {
        let category: CleanupCategory
        var entries: [Entry]
        var expanded = false
        var id: String { category.id }
        var total: UInt64 { entries.reduce(0) { $0 + ($1.size ?? 0) } }
        var selectedSize: UInt64 { entries.filter(\.selected).reduce(0) { $0 + ($1.size ?? 0) } }
        var selectedCount: Int { entries.filter(\.selected).count }
    }

    var phase: Phase = .idle
    var groups: [Group] = []
    var measured = 0
    var itemCount = 0
    var freed: UInt64 = 0
    var trashed: UInt64 = 0
    var failures: [String] = []

    var selectedSize: UInt64 { groups.reduce(0) { $0 + $1.selectedSize } }
    var totalSize: UInt64 { groups.reduce(0) { $0 + $1.total } }
    var selectedCount: Int { groups.reduce(0) { $0 + $1.selectedCount } }
    var selectedTrashCount: Int { groups.flatMap(\.entries).filter { $0.selected && $0.item.mode == .trash }.count }

    func scan() async {
        guard phase != .scanning && phase != .cleaning else { return }
        phase = .scanning
        freed = 0
        trashed = 0
        failures = []
        measured = 0
        let categories = await Task.detached { CleanupCatalog.build() }.value
        groups = categories.map { category in
            Group(category: category, entries: category.items.map {
                Entry(item: $0, displayName: Self.friendlyName($0.title), size: nil, selected: $0.defaultSelected)
            })
        }
        let items = categories.flatMap(\.items)
        itemCount = items.count
        await withTaskGroup(of: (String, UInt64).self) { group in
            for item in items {
                group.addTask { (item.id, DirectorySize.of(item.url)) }
            }
            for await (id, size) in group {
                setSize(id, size)
                measured += 1
            }
        }
        for g in groups.indices {
            groups[g].entries.removeAll { ($0.size ?? 0) == 0 }
            groups[g].entries.sort { ($0.size ?? 0) > ($1.size ?? 0) }
        }
        groups.removeAll { $0.entries.isEmpty }
        phase = .ready
    }

    func clean() async {
        guard phase == .ready || phase == .done else { return }
        let selected = groups.flatMap(\.entries).filter(\.selected)
        guard !selected.isEmpty else { return }
        phase = .cleaning
        let results = await Task.detached {
            selected.map { entry -> (id: String, before: UInt64, after: UInt64, trash: Bool, outcome: CleanupOutcome) in
                let outcome = CleanupEngine.clean(entry.item)
                let after = FileManager.default.fileExists(atPath: entry.item.url.path) ? DirectorySize.of(entry.item.url) : 0
                return (entry.id, entry.size ?? 0, after, entry.item.mode == .trash, outcome)
            }
        }.value
        freed = 0
        trashed = 0
        failures = []
        for r in results {
            let delta = r.before > r.after ? r.before - r.after : 0
            if r.trash { trashed += delta } else { freed += delta }
            failures += r.outcome.failures
            setSize(r.id, r.after)
        }
        for g in groups.indices {
            for e in groups[g].entries.indices where groups[g].entries[e].selected {
                groups[g].entries[e].selected = false
            }
            groups[g].entries.removeAll { ($0.size ?? 0) == 0 }
        }
        groups.removeAll { $0.entries.isEmpty }
        phase = .done
        MonitorStore.shared.refreshVolumes()
    }

    func isSelected(_ id: String) -> Bool {
        groups.lazy.flatMap(\.entries).first { $0.id == id }?.selected ?? false
    }

    func setSelected(_ id: String, _ selected: Bool) {
        for g in groups.indices {
            if let e = groups[g].entries.firstIndex(where: { $0.id == id }) {
                groups[g].entries[e].selected = selected
                return
            }
        }
    }

    func toggleExpanded(_ groupID: String) {
        if let g = groups.firstIndex(where: { $0.id == groupID }) { groups[g].expanded.toggle() }
    }

    func setAll(_ selected: Bool, in groupID: String) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for e in groups[g].entries.indices { groups[g].entries[e].selected = selected }
    }

    private func setSize(_ id: String, _ size: UInt64) {
        for g in groups.indices {
            if let e = groups[g].entries.firstIndex(where: { $0.id == id }) {
                groups[g].entries[e].size = size
                return
            }
        }
    }

    static let knownNames: [String: String] = [
        "Homebrew": "Homebrew downloads", "pip": "Python pip", "go-build": "Go build cache", "Yarn": "Yarn",
        "ms-playwright": "Playwright browsers", "node-gyp": "node-gyp headers", "CocoaPods": "CocoaPods",
        "pnpm": "pnpm", "typescript": "TypeScript", "org.swift.swiftpm": "Swift Package Manager",
        "SiriTTS": "Siri voices", "deno": "Deno", "electron": "Electron downloads", "puppeteer": "Puppeteer browsers",
    ]

    static func friendlyName(_ raw: String) -> String {
        if let known = knownNames[raw] { return known }
        if raw.contains("."), !raw.contains(" "),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            return name
        }
        return raw
    }

    @ObservationIgnored private static var iconCache: [String: Image] = [:]

    static func icon(for entry: Entry) -> Image {
        if let cached = iconCache[entry.id] { return cached }
        let raw = entry.item.title
        let store = MonitorStore.shared
        var image: Image
        if raw.contains("."), !raw.contains(" "), entry.item.mode != .trash,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) {
            image = store.icon(for: url.path)
        } else if entry.item.mode == .trash {
            image = store.icon(for: entry.item.url.path)
        } else if entry.item.url.lastPathComponent == ".Trash" {
            image = MonitorStore.bitmap(NSWorkspace.shared.icon(forFile: entry.item.url.path))
        } else {
            image = store.folderIcon()
        }
        iconCache[entry.id] = image
        return image
    }
}

@MainActor @Observable
final class LargeFilesModel {
    enum Phase { case idle, scanning, done }

    static let thresholds: [UInt64] = [100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000]

    var phase: Phase = .idle
    var threshold: UInt64 = UInt64(UserDefaults.standard.integer(forKey: "largeFileThreshold")).nonZero ?? 500_000_000 {
        didSet { UserDefaults.standard.set(Int(threshold), forKey: "largeFileThreshold") }
    }
    var scanned = 0
    var files: [LargeFile] = []
    var selection: Set<String> = []
    var trashedBytes: UInt64 = 0
    var lastError: String?
    var rootPath = Paths.home.path

    @ObservationIgnored private var scanner: LargeFileScanner?

    var selectedSize: UInt64 { files.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func scan(root: URL? = nil) {
        scanner?.cancel()
        let scanner = root.map { LargeFileScanner(root: $0, minimumSize: threshold, excluded: []) }
            ?? .homeScanner(minimumSize: threshold)
        self.scanner = scanner
        rootPath = scanner.root.path
        phase = .scanning
        files = []
        selection = []
        scanned = 0
        trashedBytes = 0
        lastError = nil
        Task {
            let found = await Task.detached {
                scanner.scan { count in
                    DispatchQueue.main.async { self.scanned = count }
                }
            }.value
            guard self.scanner === scanner else { return }
            files = found
            phase = .done
        }
    }

    func cancel() {
        scanner?.cancel()
    }

    func reveal(_ files: [LargeFile]) {
        NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
    }

    func trashSelected() {
        var failures: [String] = []
        for file in files where selection.contains(file.id) {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                trashedBytes += file.size
                files.removeAll { $0.id == file.id }
            } catch {
                failures.append(file.url.lastPathComponent)
            }
        }
        selection = selection.filter { id in files.contains { $0.id == id } }
        lastError = failures.isEmpty ? nil : "Couldn’t move \(failures.joined(separator: ", ")) to the Trash."
    }
}

private extension UInt64 {
    var nonZero: UInt64? { self == 0 ? nil : self }
}

@MainActor @Observable
final class MaintenanceModel {
    enum State: Equatable {
        case idle, running, success(String), failure(String), cancelled
    }

    let tasks = MaintenanceCatalog.all()
    var states: [String: State] = [:]
    var lastRun: [String: Date] = [:]

    func state(_ id: String) -> State { states[id] ?? .idle }

    func task(_ id: String) -> MaintenanceTask? { tasks.first { $0.id == id } }

    func run(_ task: MaintenanceTask) async {
        guard state(task.id) != .running else { return }
        states[task.id] = .running
        let before = await Self.measure(task.effect)
        let result = await task.run()
        if result.cancelled {
            states[task.id] = .cancelled
            return
        }
        guard result.succeeded else {
            states[task.id] = .failure(result.summary.isEmpty ? "Failed with status \(result.status)" : result.summary)
            return
        }
        // Freed memory and disk space settle over a moment.
        try? await Task.sleep(for: .milliseconds(task.effect == .none ? 0 : 900))
        let after = await Self.measure(task.effect)
        var message = task.successMessage
        if after > before, after - before > 1_000_000 {
            let delta = after - before
            message = task.effect == .memory ? "Freed \(Fmt.memory(delta)) of memory" : "Reclaimed \(Fmt.storage(delta))"
        }
        states[task.id] = .success(message)
        lastRun[task.id] = Date()
        if task.effect == .disk { MonitorStore.shared.refreshVolumes() }
    }

    private static func measure(_ effect: MaintenanceEffect) async -> UInt64 {
        switch effect {
        case .none: return 0
        case .memory: return await Task.detached { MemorySampler().sample().free }.value
        case .disk: return await Task.detached { DiskSampler.volumes().first { $0.isRoot }?.available ?? 0 }.value
        }
    }
}
