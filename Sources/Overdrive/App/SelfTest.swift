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

        // Junk scan and clean
        store.page = .cleanup
        store.cleanupTab = .junk
        await store.cleanup.scan()
        let entries = store.cleanup.groups.flatMap(\.entries)
        check(store.cleanup.phase == .ready, "scan finished")
        check(entries.contains { $0.item.title == "com.google.Chrome" && $0.selected }, "Chrome cache found and preselected")
        check(entries.contains { $0.item.title == "com.apple.Safari" && !$0.selected }, "Safari (com.apple) cache found, not preselected")
        check(entries.contains { $0.item.title == "Installer.dmg" && !$0.selected }, "installer in Downloads found, not preselected")
        let selected = store.cleanup.selectedSize
        check(selected > 100_000_000, "selected \(Fmt.storage(selected)) of \(Fmt.storage(store.cleanup.totalSize))")
        for i in store.cleanup.groups.indices { store.cleanup.groups[i].expanded = true }
        await pause("cleanup-ready")

        await store.cleanup.clean()
        let fm = FileManager.default
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
        check(!store.largeFiles.files.contains { $0.url.path.contains("/Library/") }, "Library excluded from large files")
        if let big { store.largeFiles.selection = [big.id] }
        await pause("large-files")
        store.largeFiles.trashSelected()
        check(!fm.fileExists(atPath: home.appending(path: "Movies/OverdriveTestBig.mov").path), "big file moved to Trash")
        check(store.largeFiles.trashedBytes > 100_000_000, "trashed bytes reported")
        await pause("large-files-trashed")

        // Processes: quit a disposable child
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["600"]
        try? child.run()
        try? await Task.sleep(for: .seconds(store.refreshInterval * 2 + 1))
        store.page = .processes
        let row = store.rows(grouped: false).first { $0.pids == [child.processIdentifier] }
        check(row != nil, "spawned process \(child.processIdentifier) is listed")
        if let row { store.quit(row, force: false) }
        try? await Task.sleep(for: .seconds(1))
        check(!child.isRunning, "Quit terminated it (status \(child.isRunning ? -1 : Int(child.terminationStatus)))")
        let grouped = store.rows(grouped: true)
        check(grouped.contains { $0.count > 1 && $0.bundlePath != nil }, "apps with helpers are grouped")
        await pause("processes")

        // Maintenance: a harmless, non-admin task through the same path as the Run button
        store.page = .maintenance
        if let task = store.maintenance.task("quicklook") {
            await store.maintenance.run(task)
            if case .success = store.maintenance.state("quicklook") { check(true, "Reset Quick Look succeeded") }
            else { check(false, "Reset Quick Look: \(store.maintenance.state("quicklook"))") }
        }
        await pause("maintenance")

        // Launch at login round trip
        let before = store.launchAtLogin
        let err = store.setLaunchAtLogin(!before)
        check(err == nil && (store.launchAtLogin != before || SMAppService.mainApp.status == .requiresApproval),
              "launch at login toggled (\(err ?? "ok"))")
        _ = store.setLaunchAtLogin(before)
        check(store.launchAtLogin == before, "launch at login restored")

        store.page = .overview
        await pause("overview")
        log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func log(_ line: String) {
        FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
    }
}

