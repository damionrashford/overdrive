import AppKit
import Observation
import OverdriveCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct ProcessRow: Identifiable, Hashable {
    let id: String
    let name: String
    let iconPath: String
    let pids: [pid_t]
    let bundlePath: String?
    let cpu: Double
    let memory: UInt64
    let threads: Int
    let diskRead: Double
    let diskWrite: Double
    /// False in the App Store edition, where only names are available.
    let hasMetrics: Bool

    var count: Int { pids.count }
}

struct Recommendation: Identifiable {
    enum Action { case page(Page), quit(ProcessRow) }

    let id: String
    let symbol: String
    let title: String
    let detail: String
    let severity: Int
    let action: Action?
    let actionLabel: String?
}

struct HealthReport {
    let score: Int
    let issues: [Recommendation]

    var label: String {
        switch score {
        case 90...: "Excellent"
        case 75..<90: "Good"
        case 50..<75: "Fair"
        default: "Strained"
        }
    }

    var colors: [Color] {
        switch score {
        case 90...: Theme.health
        case 75..<90: [Color(hex: 0xBEF264), Color(hex: 0x4ADE80)]
        case 50..<75: [Color(hex: 0xFDE68A), Color(hex: 0xF59E0B)]
        default: [Color(hex: 0xFCA5A5), Color(hex: 0xEF4444)]
        }
    }
}

enum CleanupTab { case junk, large }
enum StorageTab { case volumes, explorer }
enum AppsTab { case installed, startup }

@MainActor @Observable
final class MonitorStore {
    static let shared = MonitorStore()

    let info: SystemInfo
    let capabilities = Capabilities.current
    let settings = AppSettings()
    let access = AccessManager()
    let alerts = AlertCenter()

    var page: Page = .overview
    var cleanupTab: CleanupTab = .junk
    var storageTab: StorageTab = .volumes
    var appsTab: AppsTab = .installed

    var cpu = CPUSnapshot()
    var memory = MemorySnapshot()
    var gpu = GPUSnapshot()
    var diskIO = DiskIOSnapshot()
    var volumes: [VolumeInfo] = []
    var network = NetworkSnapshot()
    var power = PowerSnapshot()
    var processes: [ProcessSample] = []
    var thermal: ProcessInfo.ThermalState = .nominal
    var sensors = SensorSnapshot()
    var sampleCount = 0
    var sensorsAvailable = false
    /// Overdrive's own cost, shown in Settings so the person can judge it.
    var selfCPU: Double = 0
    var selfMemory: UInt64 = 0

    var cpuTotal = History()
    var cpuSystem = History()
    var perCore: [Series] = []
    var memoryUsed = History()
    var memoryPressure = History()
    var gpuDevice = History()
    var gpuRenderer = History()
    var gpuTiler = History()
    var diskRead = History()
    var diskWrite = History()
    var netDown = History()
    var netUp = History()
    var cpuTemperature = History()
    var gpuTemperature = History()
    var fanSpeed = History()
    var systemPower = History()
    var batteryLevel = History()
    var batteryPower = History()

    /// Processes waiting on the confirmation dialog in RootView.
    var pendingQuit: (row: ProcessRow, force: Bool)?

    let maintenance = MaintenanceModel()
    let cleanup = CleanupModel()
    let largeFiles = LargeFilesModel()
    let space = SpaceModel()
    let apps = AppsModel()
    let ai = AIModel()
    let updates = UpdateChecker()

    @ObservationIgnored private let engine: SamplerEngine
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var appNames: [pid_t: String] = [:]
    @ObservationIgnored private var bundleNames: [String: String] = [:]
    @ObservationIgnored private var icons: [String: Image] = [:]
    @ObservationIgnored private var lastSelf: (cpu: Double, time: Double)?

    private init() {
        let info = SystemInfo.current()
        self.info = info
        engine = SamplerEngine(chip: info.chip)
    }

    func start() {
        guard loop == nil else { return }
        alerts.refreshAuthorization()
        loop = Task { [weak self] in
            guard let self else { return }
            sensorsAvailable = await engine.sensorsAvailable
            if !capabilities.isSandboxed { Task { await updates.checkIfDue(settings: settings) } }
            // A quick second sample so CPU and per-process deltas are meaningful right away.
            await tick(includeVolumes: true)
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled {
                await tick(includeVolumes: sampleCount % 5 == 1)
                try? await Task.sleep(for: .seconds(settings.refreshInterval))
            }
        }
    }

    private func tick(includeVolumes: Bool) async {
        let s = await engine.sample(includeVolumes: includeVolumes)
        cpu = s.cpu
        memory = s.memory
        gpu = s.gpu
        diskIO = s.diskIO
        network = s.network
        power = s.power
        thermal = s.thermal
        sensors = s.sensors
        if let v = s.volumes { volumes = v }
        refreshAppNames()
        processes = s.processes

        let now = Date()
        cpuTotal.append(s.cpu.total * 100, at: now)
        cpuSystem.append(s.cpu.system * 100, at: now)
        if perCore.count != s.cpu.cores.count { perCore = s.cpu.cores.map { _ in Series(capacity: 40) } }
        for (i, v) in s.cpu.cores.enumerated() { perCore[i].append(v * 100) }
        memoryUsed.append(s.memory.usedFraction * 100, at: now)
        memoryPressure.append(s.memory.pressureFraction * 100, at: now)
        gpuDevice.append(s.gpu.device * 100, at: now)
        gpuRenderer.append(s.gpu.renderer * 100, at: now)
        gpuTiler.append(s.gpu.tiler * 100, at: now)
        diskRead.append(s.diskIO.readPerSec, at: now)
        diskWrite.append(s.diskIO.writePerSec, at: now)
        netDown.append(s.network.downPerSec, at: now)
        netUp.append(s.network.upPerSec, at: now)
        if let t = s.sensors.average(.cpu) { cpuTemperature.append(t, at: now) }
        if let t = s.sensors.average(.gpu) { gpuTemperature.append(t, at: now) }
        if let fan = s.sensors.fans.first { fanSpeed.append(fan.rpm, at: now) }
        if let w = s.sensors.systemPower { systemPower.append(w, at: now) }
        if s.power.hasBattery {
            batteryLevel.append(s.power.percent * 100, at: now)
            batteryPower.append(s.power.batteryWatts ?? 0, at: now)
        }
        sampleSelf()
        sampleCount += 1

        alerts.evaluate(store: self, settings: settings)
        await ai.observe(identities: processIdentities(), memory: s.memory, workingSet: info.gpuWorkingSet)
    }

    private func sampleSelf() {
        let reading = SelfUsage.sample()
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        if let last = lastSelf, now > last.time {
            selfCPU = max(0, (reading.cpuSeconds - last.cpu) / (now - last.time) * 100)
        }
        lastSelf = (reading.cpuSeconds, now)
        selfMemory = reading.footprint
    }

    func refreshVolumes() {
        Task {
            let v = await Task.detached { DiskSampler.volumes() }.value
            volumes = v
        }
    }

    var rootVolume: VolumeInfo? { volumes.first { $0.isRoot } ?? volumes.first }

    // MARK: Processes

    private func refreshAppNames() {
        var names: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName { names[app.processIdentifier] = name }
        }
        appNames = names
    }

    private func processIdentities() -> [ProcessIdentity] {
        processes.map { ProcessIdentity(pid: $0.pid, name: $0.name, path: $0.path) }
    }

    func displayName(forBundle path: String) -> String {
        if let cached = bundleNames[path] { return cached }
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        bundleNames[path] = name
        return name
    }

    /// Icons are cached by kind, not by path: hundreds of bare executables share one generic icon,
    /// and loading each one separately from IconServices costs ~1 MB apiece.
    func icon(for path: String) -> Image {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = ["app", "appex", "bundle", "prefpane"].contains(ext) ? path : (ext.isEmpty ? "kind:exec" : "ext:\(ext)")
        if let cached = icons[key] { return cached }
        let source: NSImage
        if key == path {
            source = NSWorkspace.shared.icon(forFile: path)
        } else if ext.isEmpty {
            source = NSWorkspace.shared.icon(for: .unixExecutable)
        } else {
            source = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
        let image = Self.bitmap(source)
        icons[key] = image
        return image
    }

    func folderIcon() -> Image {
        if let cached = icons["kind:folder"] { return cached }
        let image = Self.bitmap(NSWorkspace.shared.icon(for: .folder))
        icons["kind:folder"] = image
        return image
    }

    /// NSWorkspace icons hold many representations and are re-rasterized on every redraw; a fixed
    /// 64px CGImage is uploaded once as a texture.
    static func bitmap(_ source: NSImage, pixels: Int = 64) -> Image {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return Image(nsImage: source) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = rep.cgImage else { return Image(nsImage: source) }
        return Image(decorative: cg, scale: 2)
    }

    func rows(grouped: Bool) -> [ProcessRow] {
        guard grouped else {
            return processes.map { p in
                ProcessRow(id: "pid:\(p.pid)", name: appNames[p.pid] ?? p.name, iconPath: p.appBundlePath ?? "",
                           pids: [p.pid], bundlePath: nil, cpu: p.cpu, memory: p.memory, threads: p.threads,
                           diskRead: p.diskReadPerSec, diskWrite: p.diskWritePerSec, hasMetrics: true)
            }
        }
        var groups: [String: [ProcessSample]] = [:]
        for p in processes { groups[p.appBundlePath ?? "pid:\(p.pid)", default: []].append(p) }
        return groups.map { key, members in
            if let bundle = members.first?.appBundlePath {
                return ProcessRow(id: key, name: displayName(forBundle: bundle), iconPath: bundle, pids: members.map(\.pid),
                                  bundlePath: bundle, cpu: members.reduce(0) { $0 + $1.cpu },
                                  memory: members.reduce(0) { $0 + $1.memory }, threads: members.reduce(0) { $0 + $1.threads },
                                  diskRead: members.reduce(0) { $0 + $1.diskReadPerSec },
                                  diskWrite: members.reduce(0) { $0 + $1.diskWritePerSec }, hasMetrics: true)
            }
            let p = members[0]
            return ProcessRow(id: key, name: appNames[p.pid] ?? p.name, iconPath: "", pids: [p.pid], bundlePath: nil,
                              cpu: p.cpu, memory: p.memory, threads: p.threads,
                              diskRead: p.diskReadPerSec, diskWrite: p.diskWritePerSec, hasMetrics: true)
        }
    }

    func top(by key: KeyPath<ProcessRow, Double>, limit: Int) -> [ProcessRow] {
        Array(rows(grouped: true).sorted { $0[keyPath: key] > $1[keyPath: key] }.prefix(limit))
    }

    func topByMemory(limit: Int) -> [ProcessRow] {
        Array(rows(grouped: true).sorted { $0.memory > $1.memory }.prefix(limit))
    }

    func requestQuit(_ row: ProcessRow, force: Bool = false) {
        pendingQuit = (row, force)
    }

    func quit(_ row: ProcessRow, force: Bool) {
        if let bundle = row.bundlePath {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.path == bundle }
            if !apps.isEmpty {
                for app in apps { _ = force ? app.forceTerminate() : app.terminate() }
                return
            }
        }
        for pid in row.pids {
            if let app = NSRunningApplication(processIdentifier: pid) {
                _ = force ? app.forceTerminate() : app.terminate()
            } else if capabilities.canQuitProcesses {
                kill(pid, force ? SIGKILL : SIGTERM)
            }
        }
    }

    // MARK: Health

    var health: HealthReport {
        var score = 100
        var issues: [Recommendation] = []

        let cpuAvg = cpuTotal.average(last: 8) / 100
        if cpuAvg > 0.85 { score -= 20 } else if cpuAvg > 0.6 { score -= 8 }
        if cpuAvg > 0.5, let hog = top(by: \.cpu, limit: 1).first, hog.cpu > 60 {
            issues.append(Recommendation(id: "cpu-hog", symbol: "flame", title: "\(hog.name) is busy",
                                         detail: "Using \(Int(hog.cpu))% CPU. Quit it if you are not using it.",
                                         severity: cpuAvg > 0.85 ? 2 : 1, action: .quit(hog), actionLabel: "Quit"))
        }

        switch memory.pressure {
        case .warning:
            score -= 20
            issues.append(Recommendation(id: "mem", symbol: "memorychip", title: "Memory is under pressure",
                                         detail: "macOS is compressing and swapping. Close memory-heavy apps.",
                                         severity: 1, action: .page(.memory), actionLabel: "Review"))
        case .critical:
            score -= 35
            issues.append(Recommendation(id: "mem", symbol: "memorychip", title: "Memory pressure is critical",
                                         detail: "Apps will slow down. Quit large apps now.",
                                         severity: 2, action: .page(.memory), actionLabel: "Fix"))
        case .normal:
            break
        }
        let swapGB = Double(memory.swapUsed) / 1_073_741_824
        if swapGB > 4 {
            score -= 10
            issues.append(Recommendation(id: "swap", symbol: "arrow.left.arrow.right", title: "Heavy swap use",
                                         detail: "\(Fmt.memory(memory.swapUsed)) of memory is paged to disk. A restart clears it.",
                                         severity: 1, action: .page(.processes), actionLabel: "Processes"))
        } else if swapGB > 1 {
            score -= 4
        }

        if let root = rootVolume {
            let free = root.availableFraction
            if free < 0.05 { score -= 30 } else if free < 0.10 { score -= 18 } else if free < 0.20 { score -= 6 }
            if free < 0.20 {
                issues.append(Recommendation(id: "disk", symbol: "internaldrive", title: "Startup disk is filling up",
                                             detail: "\(Fmt.storage(root.available)) left. Clear caches and junk to make room.",
                                             severity: free < 0.10 ? 2 : 1, action: .page(.cleanup), actionLabel: "Clean Up"))
            }
        }

        switch thermal {
        case .fair: score -= 5
        case .serious:
            score -= 20
            issues.append(Recommendation(id: "thermal", symbol: "thermometer.high", title: "Your Mac is running hot",
                                         detail: "macOS is limiting performance to cool down.", severity: 2,
                                         action: .page(sensorsAvailable ? .sensors : .cpu), actionLabel: "See why"))
        case .critical: score -= 35
        default: break
        }
        if let t = sensors.average(.cpu), t >= 100 { score -= 10 }
        if power.hasBattery, let h = power.health, h < 0.8 {
            issues.append(Recommendation(id: "battery", symbol: "battery.25percent", title: "Battery health is \(Fmt.percent(h))",
                                         detail: "Below 80% Apple recommends a battery service.", severity: 1,
                                         action: .page(.battery), actionLabel: "Details"))
        }
        if gpuDevice.average(last: 8) > 90 { score -= 5 }
        return HealthReport(score: max(0, min(100, score)), issues: issues.sorted { $0.severity > $1.severity })
    }

    var thermalLabel: String {
        switch thermal {
        case .nominal: "Nominal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    var thermalColor: Color {
        switch thermal {
        case .nominal: Theme.good
        case .fair: Theme.warn
        default: Theme.bad
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Report

    /// A plain-text snapshot for support threads and bug reports.
    func report() -> String {
        var lines: [String] = []
        lines.append("Overdrive \(Bundle.main.shortVersion) (\(capabilities.editionName)) · \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("\(info.modelName) (\(info.modelIdentifier)) · \(info.chip) · \(info.coreSummary) · \(Fmt.memory(info.physicalMemory))")
        lines.append("\(info.osVersion) (\(info.osBuild)) · up \(Fmt.duration(info.uptime)) · thermal \(thermalLabel)")
        lines.append("")
        lines.append("CPU \(Fmt.percent(cpu.total)) (user \(Fmt.percent(cpu.user)), system \(Fmt.percent(cpu.system))) · load \(cpu.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " / "))")
        lines.append("Memory \(Fmt.memory(memory.used)) of \(Fmt.memory(memory.total)) · app \(Fmt.memory(memory.app)) · wired \(Fmt.memory(memory.wired)) · compressed \(Fmt.memory(memory.compressed)) · cached \(Fmt.memory(memory.cached)) · swap \(Fmt.memory(memory.swapUsed)) · pressure \(memory.pressure.label)")
        lines.append("GPU \(info.gpuName) · device \(Fmt.percent(gpu.device)) · in use \(Fmt.memory(gpu.inUseMemory))")
        for v in volumes {
            lines.append("Volume \(v.name): \(Fmt.storage(v.available)) available of \(Fmt.storage(v.total)) (purgeable \(Fmt.storage(v.purgeable)))")
        }
        lines.append("Network ↓ \(Fmt.rate(network.downPerSec)) ↑ \(Fmt.rate(network.upPerSec)) · since boot ↓ \(Fmt.storage(network.totalDown)) ↑ \(Fmt.storage(network.totalUp))")
        if power.hasBattery {
            lines.append("Battery \(Fmt.percent(power.percent)) · health \(power.health.map { Fmt.percent($0) } ?? "–") · \(power.cycleCount ?? 0) cycles · \(power.onAC ? "on power" : "on battery")\(power.batteryWatts.map { " · \(Fmt.watts($0))" } ?? "")")
        }
        if sensors.available {
            let temps = SensorGroup.allCases.compactMap { g in sensors.average(g).map { "\(g.rawValue) \(settings.temperature($0))" } }
            lines.append("Sensors " + temps.joined(separator: " · ") + sensors.fans.map { " · fan \($0.id + 1) \(Fmt.rpm($0.rpm))" }.joined()
                         + (sensors.systemPower.map { " · \(Fmt.watts($0)) total" } ?? ""))
        }
        let topCPU = top(by: \.cpu, limit: 5)
        if !topCPU.isEmpty, topCPU[0].hasMetrics {
            lines.append("")
            lines.append("Top CPU: " + topCPU.map { "\($0.name) \(String(format: "%.0f%%", $0.cpu))" }.joined(separator: ", "))
            lines.append("Top memory: " + topByMemory(limit: 5).map { "\($0.name) \(Fmt.memory($0.memory))" }.joined(separator: ", "))
        }
        if !ai.runtimes.isEmpty {
            lines.append("AI runtimes: " + ai.runtimes.map(\.name).joined(separator: ", ")
                         + (ai.loaded.isEmpty ? "" : " · loaded " + ai.loaded.map { "\($0.name) \(Fmt.memory($0.size))" }.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "0" }
}
