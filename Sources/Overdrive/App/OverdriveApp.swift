import AppKit
import OverdriveCore
import SwiftUI

@main
struct OverdriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = MonitorStore.shared

    init() {
        if CommandLine.arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
    }

    var body: some Scene {
        Window("Overdrive", id: "main") {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1120, minHeight: 740)
                .task { LaunchOptions.apply(to: store) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1300, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Array((Page.monitor + Page.optimize).enumerated()), id: \.element) { index, page in
                    Button(page.title) { store.page = page }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { store.page = .settings }.keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        MainActor.assumeIsolated { MonitorStore.shared.start() }
    }

    /// Closing the window leaves Overdrive running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Hidden flags for screenshots and smoke tests: `--page cpu`, `--scan`, `--large-root <dir>`.
enum LaunchOptions {
    @MainActor static func apply(to store: MonitorStore) {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let raw = value(after: "--page"), let page = Page(rawValue: raw) { store.page = page }
        if args.contains("--scan") { Task { await store.cleanup.scan() } }
        if args.contains("--e2e") { Task { await SelfTest.run(store) } }
        if let out = value(after: "--render-menubar") {
            Task {
                try? await Task.sleep(for: .seconds(8))
                let renderer = ImageRenderer(content: MenuBarPanel().environment(store).background(Theme.background))
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                }
                exit(0)
            }
        }
        if let root = value(after: "--large-root") {
            if let mb = value(after: "--threshold-mb").flatMap(UInt64.init) { store.largeFiles.threshold = mb * 1_000_000 }
            store.largeFiles.scan(root: URL(fileURLWithPath: root))
        }
    }
}

enum Diagnostics {
    /// Prints two samples one second apart, to compare against vm_stat, top, iostat and netstat.
    static func dump() {
        let info = SystemInfo.current()
        let cpu = CPUSampler(), memory = MemorySampler(), gpu = GPUSampler(), disk = DiskSampler()
        let network = NetworkSampler(), processes = ProcessSampler(), power = PowerSampler()
        _ = (memory.sample(), disk.sampleIO(), network.sample(), processes.sample())
        Thread.sleep(forTimeInterval: 1)
        let c = cpu.sample(), m = memory.sample(), g = gpu.sample(), d = disk.sampleIO(), n = network.sample()
        let p = processes.sample().sorted { $0.cpu > $1.cpu }, b = power.sample()
        print("model      \(info.modelName) (\(info.modelIdentifier)) · \(info.chip) · \(info.osVersion) \(info.osBuild)")
        print("clusters   \(info.clusters.map { "\($0.name)=\($0.cores)" }.joined(separator: " "))")
        print("gpu        \(info.gpuName) cores=\(info.gpuCores ?? 0) workingSet=\(Fmt.memory(info.gpuWorkingSet))")
        print("cpu        total=\(Fmt.percent(c.total, decimals: 1)) user=\(Fmt.percent(c.user, decimals: 1)) sys=\(Fmt.percent(c.system, decimals: 1)) load=\(c.loadAverage.map { String(format: "%.2f", $0) })")
        print("cores      \(c.cores.map { String(format: "%.0f", $0 * 100) }.joined(separator: " "))")
        print("memory     used=\(Fmt.memory(m.used)) app=\(Fmt.memory(m.app)) wired=\(Fmt.memory(m.wired)) compressed=\(Fmt.memory(m.compressed)) cached=\(Fmt.memory(m.cached)) free=\(Fmt.memory(m.free)) swap=\(Fmt.memory(m.swapUsed))/\(Fmt.memory(m.swapTotal)) pressure=\(m.pressure.label) \(Fmt.percent(m.pressureFraction))")
        print("gpu        device=\(Fmt.percent(g.device)) renderer=\(Fmt.percent(g.renderer)) tiler=\(Fmt.percent(g.tiler)) inUse=\(Fmt.memory(g.inUseMemory))")
        print("disk io    read=\(Fmt.rate(d.readPerSec)) write=\(Fmt.rate(d.writePerSec)) totalRead=\(Fmt.storage(d.totalRead)) totalWritten=\(Fmt.storage(d.totalWritten))")
        for v in DiskSampler.volumes() {
            print("volume     \(v.name) \(v.path) total=\(Fmt.storage(v.total)) available=\(Fmt.storage(v.available)) free=\(Fmt.storage(v.free)) purgeable=\(Fmt.storage(v.purgeable))")
        }
        print("network    down=\(Fmt.rate(n.downPerSec)) up=\(Fmt.rate(n.upPerSec)) totalDown=\(Fmt.storage(n.totalDown)) totalUp=\(Fmt.storage(n.totalUp))")
        for i in n.interfaces { print("interface  \(i.bsdName) \(i.displayName) \(i.ipv4 ?? "-")") }
        print("battery    has=\(b.hasBattery) \(Fmt.percent(b.percent)) charging=\(b.isCharging) ac=\(b.onAC) health=\(b.health.map { Fmt.percent($0) } ?? "-") cycles=\(b.cycleCount ?? 0)")
        print("processes  \(p.count) visible")
        for s in p.prefix(8) {
            print(String(format: "  %6d %6.1f%% %10@  %@", s.pid, s.cpu, Fmt.memory(s.memory), s.name))
        }
    }
}
