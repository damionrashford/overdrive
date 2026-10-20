import Foundation
import OverdriveCore

/// `--dump` and `--dump-net`: print raw samples to compare against vm_stat, top, iostat and netstat.
enum Diagnostics {
    static func dump() {
        let info = SystemInfo.current()
        let cpu = CPUSampler(), memory = MemorySampler(), gpu = GPUSampler(), disk = DiskSampler()
        let network = NetworkSampler(), processes = ProcessSampler(), power = PowerSampler()
        let sensors = Capabilities.current.canReadSensors ? SensorSampler(chip: info.chip) : nil
        _ = (memory.sample(), disk.sampleIO(), network.sample(), processes.sample())
        Thread.sleep(forTimeInterval: 1)
        let c = cpu.sample(), m = memory.sample(), g = gpu.sample(), d = disk.sampleIO(), n = network.sample()
        let p = processes.sample().sorted { $0.cpu > $1.cpu }, b = power.sample()
        print("edition    \(Capabilities.current.editionName)")
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
        print("battery    has=\(b.hasBattery) \(Fmt.percent(b.percent)) charging=\(b.isCharging) ac=\(b.onAC) health=\(b.health.map { Fmt.percent($0) } ?? "-") cycles=\(b.cycleCount ?? 0)/\(b.designCycleCount ?? 0) watts=\(b.batteryWatts.map { Fmt.watts($0) } ?? "-") adapter=\(b.adapterName ?? "-") \(b.adapterWatts ?? 0)W temp=\(b.temperatureCelsius.map { String(format: "%.1f", $0) } ?? "-") lowPower=\(b.lowPowerMode)")
        for peripheral in b.peripherals { print("peripheral \(peripheral.name) \(Fmt.percent(peripheral.percent))") }
        if let s = sensors?.sample(), s.available {
            print("sensors    cpu=\(s.average(.cpu).map { String(format: "%.1f", $0) } ?? "-")°C gpu=\(s.average(.gpu).map { String(format: "%.1f", $0) } ?? "-")°C fans=\(s.fans.map { Fmt.rpm($0.rpm) }) power=\(s.power.map { "\($0.name) \(Fmt.watts($0.watts))" })")
            print("temps      \(s.temperatures.map { "\($0.key)=\(String(format: "%.0f", $0.value))" }.joined(separator: " "))")
        }
        print("processes  \(p.count) visible")
        for s in p.prefix(8) {
            print(String(format: "  %6d %6.1f%% %10@ %10@  %@", s.pid, s.cpu, Fmt.memory(s.memory), Fmt.rate(s.diskReadPerSec + s.diskWritePerSec), s.name))
        }
    }

    /// Five one-second samples with per-interface byte deltas, to validate rate math against netstat -w.
    static func dumpNetwork() {
        let sampler = NetworkSampler()
        var last: [String: (UInt64, UInt64)] = [:]
        for _ in 0..<5 {
            let s = sampler.sample()
            var parts: [String] = []
            for i in s.interfaces {
                let p = last[i.bsdName] ?? (i.bytesIn, i.bytesOut)
                parts.append("\(i.bsdName) +\(i.bytesIn - p.0)/+\(i.bytesOut - p.1)")
                last[i.bsdName] = (i.bytesIn, i.bytesOut)
            }
            print("down=\(Fmt.rate(s.downPerSec)) up=\(Fmt.rate(s.upPerSec)) total=\(s.totalDown)/\(s.totalUp)  \(parts.joined(separator: "  "))")
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
