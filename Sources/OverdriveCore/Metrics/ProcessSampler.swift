import Darwin
import Foundation

public struct ProcessSample: Sendable, Identifiable, Hashable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let parent: pid_t
    public let name: String
    public let path: String
    /// The outermost `.app` bundle the executable lives in, so helpers can be grouped under their app.
    public let appBundlePath: String?
    /// Percent of one core; a busy multithreaded process can exceed 100, as in Activity Monitor.
    public let cpu: Double
    /// Physical footprint (Activity Monitor's "Memory" column), or resident size in the App Sandbox.
    public let memory: UInt64
    public let threads: Int
    public let diskReadPerSec: Double
    public let diskWritePerSec: Double
    public let totalDiskRead: UInt64
    public let totalDiskWritten: UInt64
    public let cpuTimeSeconds: Double
    public let startTime: Date
    /// Disk I/O comes from `proc_pid_rusage`, which the App Sandbox only allows for the app itself.
    public let hasDiskIO: Bool
}

/// Samples every process the current user can inspect. Other users' processes (root, _windowserver)
/// refuse inspection without privileges, so they are skipped; system-wide totals come from CPUSampler.
///
/// Outside the sandbox the rich `proc_pid_rusage` path is used. Inside it, process ids come from
/// `KERN_PROC_ALL` and metrics from `proc_pidinfo(PROC_PIDTASKINFO)`, which the sandbox permits.
public final class ProcessSampler {
    private struct Meta { let start: UInt64; let name: String; let path: String; let bundle: String?; let parent: pid_t }
    private struct Prev { let cpu: UInt64; let read: UInt64; let written: UInt64 }

    public let usesTaskInfo: Bool
    private var previous: [pid_t: Prev] = [:]
    private var previousWall: UInt64 = 0
    private var meta: [pid_t: Meta] = [:]
    private let ticksToNanos: Double
    private let bootTime: Date

    public init(sandboxed: Bool = Capabilities.current.isSandboxed) {
        usesTaskInfo = sandboxed
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksToNanos = timebase.denom == 0 ? 1 : Double(timebase.numer) / Double(timebase.denom)
        bootTime = Date(timeIntervalSinceNow: -Double(mach_absolute_time()) * ticksToNanos / 1e9)
    }

    public func sample() -> [ProcessSample] {
        let wall = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousWall == 0 ? 0 : Double(wall - previousWall)
        previousWall = wall
        var current: [pid_t: Prev] = [:]
        let samples = usesTaskInfo ? sampleTaskInfo(elapsed: elapsed, current: &current)
                                   : sampleRusage(elapsed: elapsed, current: &current)
        previous = current
        meta = meta.filter { current[$0.key] != nil }
        return samples
    }

    private func sampleRusage(elapsed: Double, current: inout [pid_t: Prev]) -> [ProcessSample] {
        var samples: [ProcessSample] = []
        for pid in Self.allPIDs() where pid > 0 {
            var usage = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard ok == 0 else { continue }
            // rusage times are mach ticks on Apple Silicon despite the header saying nanoseconds.
            let cpuNanos = UInt64(Double(usage.ri_user_time + usage.ri_system_time) * ticksToNanos)
            let now = Prev(cpu: cpuNanos, read: usage.ri_diskio_bytesread, written: usage.ri_diskio_byteswritten)
            current[pid] = now

            let info = metadata(for: pid, start: usage.ri_proc_start_abstime, parent: nil)
            var cpu = 0.0, readRate = 0.0, writeRate = 0.0
            if elapsed > 0, let before = previous[pid] {
                let seconds = elapsed / 1e9
                cpu = Double(positiveDelta(cpuNanos, before.cpu)) / elapsed * 100
                readRate = Double(positiveDelta(now.read, before.read)) / seconds
                writeRate = Double(positiveDelta(now.written, before.written)) / seconds
            }
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let threads = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize ? Int(task.pti_threadnum) : 0
            samples.append(ProcessSample(
                pid: pid, parent: info.parent, name: info.name, path: info.path, appBundlePath: info.bundle,
                cpu: cpu, memory: usage.ri_phys_footprint, threads: threads,
                diskReadPerSec: readRate, diskWritePerSec: writeRate,
                totalDiskRead: usage.ri_diskio_bytesread, totalDiskWritten: usage.ri_diskio_byteswritten,
                cpuTimeSeconds: Double(cpuNanos) / 1e9,
                startTime: bootTime.addingTimeInterval(Double(usage.ri_proc_start_abstime) * ticksToNanos / 1e9),
                hasDiskIO: true
            ))
        }
        return samples
    }

    private func sampleTaskInfo(elapsed: Double, current: inout [pid_t: Prev]) -> [ProcessSample] {
        var samples: [ProcessSample] = []
        let uid = getuid()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        for entry in ProcessDirectory.list() where entry.uid == uid {
            var task = proc_taskinfo()
            guard proc_pidinfo(entry.pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { continue }
            // Like rusage, proc_taskinfo times are mach ticks on Apple Silicon.
            let cpuNanos = UInt64(Double(task.pti_total_user + task.pti_total_system) * ticksToNanos)
            current[entry.pid] = Prev(cpu: cpuNanos, read: 0, written: 0)
            let startKey = UInt64(entry.startTime.timeIntervalSince1970)
            let info = metadata(for: entry.pid, start: startKey, parent: entry.parent, fallbackName: entry.name)
            var cpu = 0.0
            if elapsed > 0, let before = previous[entry.pid] {
                cpu = Double(positiveDelta(cpuNanos, before.cpu)) / elapsed * 100
            }
            samples.append(ProcessSample(
                pid: entry.pid, parent: entry.parent, name: info.name, path: info.path, appBundlePath: info.bundle,
                cpu: cpu, memory: task.pti_resident_size, threads: Int(task.pti_threadnum),
                diskReadPerSec: 0, diskWritePerSec: 0, totalDiskRead: 0, totalDiskWritten: 0,
                cpuTimeSeconds: Double(cpuNanos) / 1e9, startTime: entry.startTime, hasDiskIO: false
            ))
        }
        return samples
    }

    private func metadata(for pid: pid_t, start: UInt64, parent: pid_t?, fallbackName: String = "") -> Meta {
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
        if name.isEmpty { name = fallbackName }
        let ppid: pid_t
        if let parent {
            ppid = parent
        } else {
            var bsd = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            ppid = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize ? pid_t(bsd.pbi_ppid) : 0
        }
        let entry = Meta(start: start, name: name.isEmpty ? "pid \(pid)" : name, path: path,
                         bundle: Self.outermostApp(in: path), parent: ppid)
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

/// Every process by name from `KERN_PROC_ALL`, which works in every edition.
public enum ProcessDirectory {
    public struct Entry: Sendable, Hashable {
        public let pid: pid_t
        public let parent: pid_t
        public let name: String
        public let uid: uid_t
        public let startTime: Date
    }

    public static func list() -> [Entry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&mib, 4, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: length / MemoryLayout<kinfo_proc>.stride + 1)
        guard sysctl(&mib, 4, &buffer, &length, nil, 0) == 0 else { return [] }
        let count = length / MemoryLayout<kinfo_proc>.stride
        return buffer.prefix(count).compactMap { proc in
            var p = proc
            let name = withUnsafePointer(to: &p.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
            guard p.kp_proc.p_pid > 0 else { return nil }
            let start = Date(timeIntervalSince1970: Double(p.kp_proc.p_starttime.tv_sec))
            return Entry(pid: p.kp_proc.p_pid, parent: p.kp_eproc.e_ppid, name: name, uid: p.kp_eproc.e_ucred.cr_uid, startTime: start)
        }
    }
}

/// CPU and memory of Overdrive itself, available in every edition (the sandbox allows self-inspection).
public enum SelfUsage {
    public struct Reading: Sendable {
        public let cpuSeconds: Double
        public let footprint: UInt64
    }

    private static let ticksToNanos: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return timebase.denom == 0 ? 1 : Double(timebase.numer) / Double(timebase.denom)
    }()

    public static func sample() -> Reading {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
        }
        guard ok == 0 else { return Reading(cpuSeconds: 0, footprint: 0) }
        return Reading(cpuSeconds: Double(usage.ri_user_time + usage.ri_system_time) * ticksToNanos / 1e9,
                       footprint: usage.ri_phys_footprint)
    }
}
