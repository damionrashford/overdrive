import AppKit
import Observation
import OverdriveCore

/// Installed apps with their leftovers, and launchd startup items.
@MainActor @Observable
final class AppsModel {
    var apps: [InstalledApp] = []
    var loadingApps = false
    var measured = 0

    var selected: InstalledApp?
    var leftovers: [LeftoverItem] = []
    var selection: Set<String> = []
    var includeApp = true
    var findingLeftovers = false
    var outcome: AppInventory.UninstallOutcome?

    var startupItems: [StartupItem] = []
    var startupLoaded = false
    var startupMessage: String?

    @ObservationIgnored private var sizeTask: Task<Void, Never>?

    var selectedLeftoverBytes: UInt64 { leftovers.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func loadApps() async {
        guard !loadingApps else { return }
        loadingApps = true
        apps = await Task.detached { AppInventory.list() }.value
        measured = 0
        loadingApps = false
        sizeTask?.cancel()
        let list = apps
        sizeTask = Task { [weak self] in
            // Sizes stream in as they are measured; the list stays usable meanwhile.
            await withTaskGroup(of: (String, UInt64).self) { group in
                var iterator = list.makeIterator()
                var running = 0
                func enqueue(_ app: InstalledApp) {
                    group.addTask { (app.id, DirectorySize.of(app.url)) }
                }
                while running < 4, let app = iterator.next() { enqueue(app); running += 1 }
                for await (id, size) in group {
                    guard let self, !Task.isCancelled else { return }
                    if let i = apps.firstIndex(where: { $0.id == id }) { apps[i].size = size }
                    if selected?.id == id { selected?.size = size }
                    measured += 1
                    if let next = iterator.next() { enqueue(next) }
                }
            }
        }
    }

    func select(_ app: InstalledApp?) async {
        selected = app
        leftovers = []
        selection = []
        outcome = nil
        includeApp = true
        guard let app else { return }
        findingLeftovers = true
        let found = await Task.detached { AppInventory.leftovers(for: app) }.value
        guard selected?.id == app.id else { return }
        leftovers = found
        selection = Set(found.filter { !$0.requiresAdmin }.map(\.id))
        findingLeftovers = false
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == app.url.standardizedFileURL.path }
    }

    func quit(_ app: InstalledApp) {
        for running in NSWorkspace.shared.runningApplications where running.bundleURL?.standardizedFileURL.path == app.url.standardizedFileURL.path {
            running.terminate()
        }
    }

    func uninstall() async {
        guard let app = selected else { return }
        let chosen = leftovers.filter { selection.contains($0.id) }
        let include = includeApp
        let result = await Task.detached { AppInventory.uninstall(app, leftovers: chosen, includeApp: include) }.value
        outcome = result
        let trashed = Set(result.trashed.map(\.path))
        leftovers.removeAll { trashed.contains($0.url.path) }
        selection = selection.filter { !trashed.contains($0) }
        if include, trashed.contains(app.url.path) {
            apps.removeAll { $0.id == app.id }
            selected = nil
        }
        MonitorStore.shared.refreshVolumes()
    }

    // MARK: Startup items

    func loadStartup() async {
        var items = await Task.detached { StartupItems.list() }.value
        if Capabilities.current.canRunShell {
            let uid = getuid()
            let output = await Shell.sh("/bin/launchctl print-disabled gui/\(uid); /bin/launchctl print-disabled system").output
            let disabled = StartupItems.parseDisabled(output)
            for i in items.indices { items[i].disabled = disabled.contains(items[i].label) }
        }
        startupItems = items
        startupLoaded = true
    }

    /// Direct edition only: `launchctl` bootout/bootstrap of a user agent. Daemons need an administrator.
    func setStartup(_ item: StartupItem, enabled: Bool) async {
        guard Capabilities.current.canRunShell else { return }
        let uid = getuid()
        let target: String
        switch item.scope {
        case .userAgent, .globalAgent: target = "gui/\(uid)"
        case .daemon: target = "system"
        }
        let path = Shell.quoted(item.url.path)
        let command = enabled
            ? "/bin/launchctl enable \(target)/\(item.label); /bin/launchctl bootstrap \(target) \(path)"
            : "/bin/launchctl bootout \(target)/\(item.label); /bin/launchctl disable \(target)/\(item.label)"
        let result = item.scope == .daemon
            ? await Shell.runAsAdmin(command, prompt: "Overdrive needs your password to change a system daemon.")
            : await Shell.sh(command)
        if result.cancelled {
            startupMessage = "Cancelled."
        } else if result.succeeded || result.output.contains("already") || result.output.isEmpty {
            startupMessage = "\(item.label) \(enabled ? "enabled" : "disabled")."
        } else {
            startupMessage = result.summary
        }
        await loadStartup()
    }

    func trashStartup(_ item: StartupItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            startupItems.removeAll { $0.id == item.id }
            startupMessage = "Moved \(item.url.lastPathComponent) to the Trash. It will not load at next login."
        } catch {
            startupMessage = (error as NSError).localizedDescription
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
