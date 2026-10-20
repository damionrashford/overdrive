import Darwin
import Foundation

public struct ProcessSample: Sendable, Identifiable, Hashable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let path: String
    /// The outermost `.app` bundle the executable lives in, so helpers can be grouped under their app.
    public let appBundlePath: String?
    /// Percent of one core; a busy multithreaded process can exceed 100, as in Activity Monitor.
    public let cpu: Double
    /// Physical footprint (Activity Monitor's "Memory" column).
    public let memory: UInt64
    public let threads: Int
}

/// Samples every process the current user can inspect. Other users' processes (root, _windowserver)
/// refuse `proc_pid_rusage` without privileges, so they are skipped; system-wide totals come from CPUSampler.
public final class ProcessSampler {
    private struct Meta { let start: UInt64; let name: String; let path: String; let bundle: String? }

    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousWall: UInt64 = 0
    private var meta: [pid_t: Meta] = [:]
    private let ticksToNanos: Double

    public init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksToNanos = timebase.denom == 0 ? 1 : Double(timebase.numer) / Double(timebase.denom)
    }

    public func sample() -> [ProcessSample] {
        let wall = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousWall == 0 ? 0 : Double(wall - previousWall)
        previousWall = wall

        var currentCPU: [pid_t: UInt64] = [:]
        var samples: [ProcessSample] = []
        for pid in Self.allPIDs() where pid > 0 {
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard ok == 0 else { continue }
            // rusage times are mach ticks on Apple Silicon despite the header saying nanoseconds.
            let cpuNanos = UInt64(Double(usage.ri_user_time + usage.ri_system_time) * ticksToNanos)
            currentCPU[pid] = cpuNanos

            let info = metadata(for: pid, start: usage.ri_proc_start_abstime)
            var cpu = 0.0
            if elapsed > 0, let before = previousCPU[pid], cpuNanos >= before {
                cpu = Double(cpuNanos - before) / elapsed * 100
            }
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let threads = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize ? Int(task.pti_threadnum) : 0
            samples.append(ProcessSample(
                pid: pid, name: info.name, path: info.path, appBundlePath: info.bundle,
                cpu: cpu, memory: usage.ri_phys_footprint, threads: threads
            ))
        }
        previousCPU = currentCPU
        meta = meta.filter { currentCPU[$0.key] != nil }
        return samples
    }

    private func metadata(for pid: pid_t, start: UInt64) -> Meta {
        if let cached = meta[pid], cached.start == start { return cached }
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : ""
        var name = (path as NSString).lastPathComponent
        if name.isEmpty {
            var short = [CChar](repeating: 0, count: 256)
            proc_name(pid, &short, UInt32(short.count))
            name = short.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        let entry = Meta(start: start, name: name.isEmpty ? "pid \(pid)" : name, path: path, bundle: Self.outermostApp(in: path))
        meta[pid] = entry
        return entry
    }

    static func outermostApp(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }
}
