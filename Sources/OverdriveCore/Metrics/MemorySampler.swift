import Darwin
import Foundation

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
}

public struct MemorySnapshot: Sendable {
    public var total: UInt64 = 0
    public var app: UInt64 = 0
    public var wired: UInt64 = 0
    public var compressed: UInt64 = 0
    public var cached: UInt64 = 0
    public var free: UInt64 = 0
    public var swapTotal: UInt64 = 0
    public var swapUsed: UInt64 = 0
    public var pressure: MemoryPressure = .normal
    /// 0...1, derived from the kernel's memorystatus level (what `memory_pressure` prints).
    public var pressureFraction: Double = 0
    public var pageInsPerSec: Double = 0
    public var pageOutsPerSec: Double = 0
    public var swapInsPerSec: Double = 0
    public var swapOutsPerSec: Double = 0

    /// Matches Activity Monitor's "Memory Used": app + wired + compressed.
    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }

    public init() {}
}

public final class MemorySampler {
    private let host = mach_host_self()
    private let pageSize = UInt64(Sysctl.integer("hw.pagesize") ?? 16384)
    private let total = UInt64(Sysctl.integer("hw.memsize") ?? 0)
    private var previous: (time: Double, pageins: UInt64, pageouts: UInt64, swapins: UInt64, swapouts: UInt64)?

    public init() {}

    public func sample() -> MemorySnapshot {
        var snap = MemorySnapshot()
        snap.total = total
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            snap.app = (internalPages > purgeable ? internalPages - purgeable : 0) * pageSize
            snap.wired = UInt64(stats.wire_count) * pageSize
            snap.compressed = UInt64(stats.compressor_page_count) * pageSize
            snap.cached = (UInt64(stats.external_page_count) + purgeable) * pageSize
            let accounted = snap.used + snap.cached
            snap.free = total > accounted ? total - accounted : 0

            let now = monotonicSeconds()
            let counters = (now, stats.pageins, stats.pageouts, stats.swapins, stats.swapouts)
            if let p = previous, now > p.time {
                let dt = now - p.time
                snap.pageInsPerSec = Double(positiveDelta(counters.1, p.pageins)) / dt
                snap.pageOutsPerSec = Double(positiveDelta(counters.2, p.pageouts)) / dt
                snap.swapInsPerSec = Double(positiveDelta(counters.3, p.swapins)) / dt
                snap.swapOutsPerSec = Double(positiveDelta(counters.4, p.swapouts)) / dt
            }
            previous = counters
        }
        if let swap = Sysctl.raw("vm.swapusage", as: xsw_usage.self, initial: xsw_usage()) {
            snap.swapTotal = swap.xsu_total
            snap.swapUsed = swap.xsu_used
        }
        if let level = Sysctl.integer("kern.memorystatus_vm_pressure_level") {
            snap.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }
        if let freePercent = Sysctl.integer("kern.memorystatus_level") {
            snap.pressureFraction = max(0, min(1, Double(100 - freePercent) / 100))
        }
        return snap
    }
}
