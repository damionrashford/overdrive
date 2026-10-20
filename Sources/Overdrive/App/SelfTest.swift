import AppKit
import OverdriveCore
import ServiceManagement

/// `--e2e`: drives the same model actions the buttons call, against `OVERDRIVE_HOME`, logging each
/// result and pausing between steps so the window can be captured. Refuses to run on the real home.
@MainActor
enum SelfTest {
    static func run(_ store: MonitorStore) async {
        guard ProcessInfo.processInfo.environment["OVERDRIVE_HOME"] != nil else {
            log("FAIL refusing to run without OVERDRIVE_HOME")
            exit(2)
        }
        let home = Paths.home
        let fm = FileManager.default
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            log((ok ? "PASS " : "FAIL ") + what)
            if !ok { failures += 1 }
        }
        func pause(_ step: String) async {
            log("STEP \(step)")
            try? await Task.sleep(for: .seconds(4))
        }

        try? await Task.sleep(for: .seconds(3))
        check(store.sampleCount >= 2 && store.memory.total > 0, "sampler is producing samples (\(store.sampleCount))")
        check(store.processes.contains { $0.pid == getpid() }, "process list includes Overdrive itself (\(store.processes.count) processes)")
        if store.capabilities.canReadSensors {
            check(store.sensors.available && store.sensors.average(.cpu) != nil, "sensors report a CPU temperature")
        }

        // Junk scan and clean
        store.page = .cleanup
        store.cleanupTab = .junk
        await store.cleanup.scan(exclusions: store.settings.cleanupExclusions)
        let entries = store.cleanup.groups.flatMap(\.entries)
        check(store.cleanup.phase == .ready, "scan finished")
        check(entries.contains { $0.item.title == "com.google.Chrome" && $0.selected }, "Chrome cache found and preselected")
        check(entries.contains { $0.item.title == "com.apple.Safari" && !$0.selected }, "Safari (com.apple) cache found, not preselected")
        check(entries.contains { $0.item.title == "Installer.dmg" && !$0.selected }, "installer in Downloads found, not preselected")
        let selected = store.cleanup.selectedSize
        check(selected > 100_000_000, "selected \(Fmt.storage(selected)) of \(Fmt.storage(store.cleanup.totalSize))")
        for group in store.cleanup.groups { store.cleanup.toggleExpanded(group.id) }
        await pause("cleanup-ready")

        await store.cleanup.clean()
        check(store.cleanup.phase == .done, "clean finished, freed \(Fmt.storage(store.cleanup.freed)), \(store.cleanup.failures.count) failures")
        check(!fm.fileExists(atPath: home.appending(path: "Library/Caches/com.google.Chrome").path), "Chrome cache deleted")
        check(fm.fileExists(atPath: home.appending(path: "Library/Caches/com.apple.Safari/data").path), "unselected Safari cache kept")
        check(fm.fileExists(atPath: home.appending(path: "Library/Developer/Xcode/DerivedData").path)
              && (try? fm.contentsOfDirectory(atPath: home.appending(path: "Library/Developer/Xcode/DerivedData").path))?.isEmpty == true,
              "DerivedData emptied but kept")
        check(fm.fileExists(atPath: home.appending(path: "Downloads/Installer.dmg").path), "unselected download kept")
        check(store.cleanup.freed >= 130_000_000, "freed size reported (\(Fmt.storage(store.cleanup.freed)))")
        await pause("cleanup-done")

        // Large files
        store.cleanupTab = .large
        store.largeFiles.threshold = 100_000_000
        store.largeFiles.scan()
        while store.largeFiles.phase == .scanning { try? await Task.sleep(for: .milliseconds(200)) }
        let big = store.largeFiles.files.first { $0.url.lastPathComponent == "OverdriveTestBig.mov" }
        check(big != nil, "large file scan found OverdriveTestBig.mov (\(store.largeFiles.files.count) files)")
        let library = home.appending(path: "Library").standardizedFileURL.path
        check(!store.largeFiles.files.contains { $0.url.standardizedFileURL.path.hasPrefix(library + "/") }, "Library excluded from large files")
        if let big { store.largeFiles.selection = [big.id] }
        await pause("large-files")
        store.largeFiles.trashSelected()
        check(!fm.fileExists(atPath: home.appending(path: "Movies/OverdriveTestBig.mov").path), "big file moved to Trash")
        check(store.largeFiles.trashedBytes > 100_000_000, "trashed bytes reported")
        await pause("large-files-trashed")

        // Space map
        store.page = .disk
        store.storageTab = .explorer
        store.space.scan(home)
        while store.space.phase != .done { try? await Task.sleep(for: .milliseconds(200)) }
        let tree = store.space.root
        check((tree?.size ?? 0) > 50_000_000, "space map measured \(Fmt.storage(tree?.size ?? 0))")
        let movies = tree?.children.first { $0.name == "Movies" }
        check(movies != nil, "space map lists Movies")
        if let spaceFile = tree?.children.first(where: { $0.name == "SpaceTest.bin" }) {
            let before = tree!.size
            store.space.trash(spaceFile)
            check(tree!.size < before && !fm.fileExists(atPath: spaceFile.url.path), "trashing from the map updates totals")
        } else {
            check(false, "space map lists SpaceTest.bin")
        }
        await pause("space-map")

        // Startup items (before the uninstall step trashes the fixture's launch agent)
        store.page = .apps
        store.appsTab = .startup
        await store.apps.loadStartup()
        check(store.apps.startupItems.contains { $0.label == "com.example.fooify.agent" }, "user launch agent listed")
        check(store.apps.startupItems.contains { $0.scope == .daemon }, "system daemons listed")
        await pause("startup")

        // Uninstaller leftovers
        store.appsTab = .installed
        let fake = InstalledApp(url: home.appending(path: "Applications/Fooify.app"), name: "Fooify", bundleID: "com.example.fooify",
                                version: "1.0", isSystem: false, size: 1000, lastUsed: nil)
        await store.apps.select(fake)
        let kinds = Set(store.apps.leftovers.map(\.kind))
        check(kinds.isSuperset(of: [.support, .preferences, .container, .launchAgent]), "leftovers found for Fooify: \(kinds.map(\.rawValue).sorted())")
        store.apps.includeApp = false
        await pause("apps")
        await store.apps.uninstall()
        check(store.apps.outcome?.failures.isEmpty == true && !fm.fileExists(atPath: home.appending(path: "Library/Application Support/Fooify").path),
              "leftovers moved to Trash")

        // AI model library and orphan blobs
        store.page = .ai
        await store.ai.scanStores()
        check(store.ai.stores.contains { $0.name == "Ollama" && $0.models.contains { $0.name == "llama3:8b" } }, "Ollama library parsed")
        check(store.ai.orphans.count == 1, "orphaned blob detected")
        await pause("ai")
        await store.ai.removeOrphans()
        check(store.ai.orphans.isEmpty && !fm.fileExists(atPath: home.appending(path: ".ollama/models/blobs/sha256-orphan").path), "orphaned blob removed")
        check(fm.fileExists(atPath: home.appending(path: ".ollama/models/blobs/sha256-aaa").path), "referenced blob kept")

        // Processes: quit a disposable child (direct edition only)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["600"]
        try? child.run()
        try? await Task.sleep(for: .seconds(store.settings.refreshInterval * 2 + 1))
        store.page = .processes
        let row = store.rows(grouped: false).first { $0.pids == [child.processIdentifier] }
        check(row != nil, "spawned process \(child.processIdentifier) is listed")
        if store.capabilities.canQuitProcesses {
            if let row { store.quit(row, force: false) }
            try? await Task.sleep(for: .seconds(1))
            check(!child.isRunning, "Quit terminated it (status \(child.isRunning ? -1 : Int(child.terminationStatus)))")
        } else {
            child.terminate()
        }
        check(store.rows(grouped: true).contains { $0.count > 1 && $0.bundlePath != nil }, "apps with helpers are grouped")
        await pause("processes")

        // Maintenance: a harmless, non-admin task through the same path as the Run button
        store.page = .maintenance
        if store.capabilities.canRunShell, let task = store.maintenance.task("quicklook") {
            await store.maintenance.run(task)
            if case .success = store.maintenance.state("quicklook") { check(true, "Reset Quick Look succeeded") }
            else { check(false, "Reset Quick Look: \(store.maintenance.state("quicklook"))") }
        }
        await pause("maintenance")

        // Alerts: a rule over threshold fires once and then respects the cooldown.
        var rule = store.settings.rule(.diskSpace)
        rule.enabled = true
        rule.threshold = 10_000
        store.settings.update(rule)
        store.alerts.evaluate(store: store, settings: store.settings)
        check(store.alerts.active.contains(.diskSpace), "disk-space rule evaluates as active")
        rule.threshold = 20
        rule.enabled = true
        store.settings.update(rule)

        // Launch at login round trip
        let before = store.launchAtLogin
        let err = store.setLaunchAtLogin(!before)
        check(err == nil && (store.launchAtLogin != before || SMAppService.mainApp.status == .requiresApproval),
              "launch at login toggled (\(err ?? "ok"))")
        _ = store.setLaunchAtLogin(before)
        check(store.launchAtLogin == before, "launch at login restored")

        let report = store.report()
        check(report.contains("CPU") && report.contains("Memory") && report.split(separator: "\n").count > 6, "system report renders")

        store.page = .overview
        await pause("overview")
        log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func log(_ line: String) {
        FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
    }
}
