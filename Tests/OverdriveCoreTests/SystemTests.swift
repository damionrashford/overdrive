import Foundation
import Testing
@testable import OverdriveCore

@Suite struct SystemTests {
    @Test func capabilitiesOutsideSandbox() {
        let c = Capabilities.current
        #expect(!c.isSandboxed)
        #expect(c.canQuitProcesses && c.hasProcessDiskIO)
        #expect(c.realHome.path.hasPrefix("/Users/"))
    }

    @Test func smcReadsFansAndTemperatures() throws {
        let reader = try #require(SMCReader())
        #expect(reader.keyCount() > 100)
        let keys = reader.allKeys()
        #expect(keys.contains { $0.name == "F0Ac" })
        if let rpm = reader.readFloat("F0Ac") { #expect(rpm >= 0 && rpm < 20000) }
    }

    @Test func sensorSamplerFindsThisChip() {
        let chip = SystemInfo.current().chip
        let sampler = SensorSampler(chip: chip)
        let snap = sampler.sample()
        #expect(snap.available)
        #expect(!snap.temperatures.isEmpty)
        #expect(snap.temperatures.allSatisfy { $0.value > 0 && $0.value < 130 })
        #expect(snap.average(.cpu) != nil)
        #expect(!snap.fans.isEmpty)
        #expect(snap.systemPower ?? 0 > 0)
    }

    @Test func generationParsing() {
        #expect(SensorSampler.generation(of: "Apple M5 Pro") == 5)
        #expect(SensorSampler.generation(of: "Apple M1") == 1)
        #expect(SensorSampler.generation(of: "Intel(R) Core(TM) i9") == 0)
    }

    @Test func processesCarryDiskIO() {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        let url = FileManager.default.temporaryDirectory.appending(path: "overdrive-io-\(UUID().uuidString)")
        try? Data(repeating: 1, count: 4_000_000).write(to: url)
        try? FileManager.default.removeItem(at: url)
        Thread.sleep(forTimeInterval: 0.3)
        let me = sampler.sample().first { $0.pid == getpid() }
        #expect(me?.hasDiskIO == true)
        #expect((me?.cpuTimeSeconds ?? 0) > 0)
        #expect(me?.startTime ?? .distantFuture < Date())
        #expect((me?.parent ?? 0) > 0)
    }

    @Test func sandboxStyleSamplingMatchesRusage() {
        // The task-info path (used in the App Sandbox) must agree with rusage on CPU time and list the same processes.
        let rich = ProcessSampler(sandboxed: false)
        let lite = ProcessSampler(sandboxed: true)
        _ = (rich.sample(), lite.sample())
        var x = 0.0
        let end = Date().addingTimeInterval(0.2)
        while Date() < end { x += cos(x) }
        let a = rich.sample().first { $0.pid == getpid() }!
        let b = lite.sample().first { $0.pid == getpid() }!
        #expect(abs(a.cpuTimeSeconds - b.cpuTimeSeconds) < max(0.05, a.cpuTimeSeconds * 0.1), "\(a.cpuTimeSeconds) vs \(b.cpuTimeSeconds)")
        #expect(b.memory > 0 && b.threads > 0 && !b.hasDiskIO && b.path == a.path)
        #expect(abs(Double(lite.sample().count - rich.sample().count)) < 20)
        #expect(x != 0)
    }

    @Test func processDirectoryListsEveryone() {
        let all = ProcessDirectory.list()
        #expect(all.count > 100)
        #expect(all.contains { $0.pid == 1 && $0.name == "launchd" })
        #expect(all.contains { $0.pid == getpid() })
    }

    @Test func powerReportsWattsOnLaptops() {
        let snap = PowerSampler().sample()
        if snap.hasBattery {
            #expect(snap.voltage ?? 0 > 5)
            #expect(snap.batteryWatts != nil)
            #expect(snap.designCycleCount ?? 0 > 0)
        }
    }

    @Test func startupItemsParse() {
        let items = StartupItems.list()
        #expect(items.contains { $0.scope == .daemon })
        #expect(items.allSatisfy { !$0.label.isEmpty })
        let disabled = StartupItems.parseDisabled("disabled services = {\n\t\"com.foo.bar\" => disabled\n\t\"com.apple.x\" => enabled\n}")
        #expect(disabled == ["com.foo.bar"])
    }

    @Test func appInventoryAndLeftovers() throws {
        let apps = AppInventory.list()
        #expect(apps.contains { $0.name == "Safari" || $0.bundleID == "com.apple.Safari" } || apps.count > 0)
        let home = FileManager.default.temporaryDirectory.appending(path: "overdrive-uninstall-\(UUID().uuidString)")
        for sub in ["Library/Application Support/Fooify", "Library/Caches/com.example.fooify", "Library/Preferences",
                    "Library/Containers/com.example.fooify/Data", "Library/Group Containers/ABC123.com.example.fooify"] {
            try FileManager.default.createDirectory(at: home.appending(path: sub), withIntermediateDirectories: true)
        }
        try Data([1, 2, 3]).write(to: home.appending(path: "Library/Preferences/com.example.fooify.plist"))
        try Data([1, 2, 3]).write(to: home.appending(path: "Library/Preferences/com.example.other.plist"))
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Fooify.app"), name: "Fooify", bundleID: "com.example.fooify",
                               version: "1", isSystem: false, size: nil, lastUsed: nil)
        let found = AppInventory.leftovers(for: app, home: home)
        let kinds = Set(found.map(\.kind))
        #expect(kinds.isSuperset(of: [.support, .cache, .preferences, .container, .groupContainer]))
        #expect(!found.contains { $0.url.lastPathComponent == "com.example.other.plist" })
    }

    @Test func spaceScannerBuildsTree() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "overdrive-space-\(UUID().uuidString)")
        for (path, bytes) in [("a/one.bin", 300_000), ("a/b/two.bin", 200_000), ("c/three.bin", 100_000), ("Pkg.app/Contents/MacOS/x", 50_000), ("big.iso", 2_000_000)] {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 9, count: bytes).write(to: url)
        }
        let tree = SpaceScanner(root: root).scan { _, _ in }
        #expect(tree.size >= 650_000)
        let a = tree.children.first { $0.name == "a" }
        #expect(a != nil && a!.size >= 500_000)
        #expect(a?.children.first?.name == "b")
        let pkg = tree.children.first { $0.name == "Pkg.app" }
        #expect(pkg?.isPackage == true && pkg?.children.isEmpty == true && (pkg?.size ?? 0) >= 50_000)
        #expect(tree.children.map(\.size) == tree.children.map(\.size).sorted(by: >))
        let iso = tree.children.first { $0.name == "big.iso" }
        #expect(iso != nil && iso?.isDirectory == false && (iso?.size ?? 0) >= 2_000_000, "large files appear beside folders")
        #expect(!tree.children.contains { $0.name == "one.bin" }, "files under the 1 MB floor stay folded into their folder")
    }
}
