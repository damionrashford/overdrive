import Darwin
import Foundation

public struct CPUSnapshot: Sendable {
    public var user: Double = 0
    public var system: Double = 0
    public var cores: [Double] = []
    public var loadAverage: [Double] = [0, 0, 0]

    public var total: Double { min(1, user + system) }
    public var idle: Double { max(0, 1 - total) }

    public init() {}
}

public final class CPUSampler {
    private struct Ticks {
        var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    }

    private let host = mach_host_self()
    private var previous: [Ticks] = []

    public init() {
        previous = read()
    }

    public func sample() -> CPUSnapshot {
        let now = read()
        var snapshot = CPUSnapshot()
        var user: UInt64 = 0, system: UInt64 = 0, total: UInt64 = 0
        for (i, cur) in now.enumerated() {
            let before = i < previous.count ? previous[i] : Ticks(user: 0, system: 0, idle: 0, nice: 0)
            // Tick counters are 32-bit and wrap, so subtract with overflow.
            let u = UInt64(cur.user &- before.user) + UInt64(cur.nice &- before.nice)
            let s = UInt64(cur.system &- before.system)
            let t = u + s + UInt64(cur.idle &- before.idle)
            snapshot.cores.append(t == 0 ? 0 : Double(u + s) / Double(t))
            user += u
            system += s
            total += t
        }
        previous = now
        if total > 0 {
            snapshot.user = Double(user) / Double(total)
            snapshot.system = Double(system) / Double(total)
        }
        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) == 3 { snapshot.loadAverage = load }
        return snapshot
    }

    private func read() -> [Ticks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { i in
            let b = i * stride
            return Ticks(
                user: UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])
            )
        }
    }
}
