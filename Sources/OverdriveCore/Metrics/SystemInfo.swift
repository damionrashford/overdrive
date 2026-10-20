import Darwin
import Foundation
import IOKit
import Metal

public struct CoreCluster: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    /// Logical CPU indices, as reported by `host_processor_info`.
    public let cores: [Int]
}

public struct SystemInfo: Sendable {
    public let modelName: String
    public let modelIdentifier: String
    public let chip: String
    public let osVersion: String
    public let osBuild: String
    public let hostName: String
    public let physicalMemory: UInt64
    public let logicalCores: Int
    public let clusters: [CoreCluster]
    public let gpuName: String
    public let gpuCores: Int?
    public let gpuWorkingSet: UInt64
    public let bootTime: Date

    public var uptime: TimeInterval { Date().timeIntervalSince(bootTime) }

    public var coreSummary: String {
        let parts = clusters.filter { !$0.cores.isEmpty }.map { "\($0.cores.count) \($0.name)" }
        return parts.count > 1 ? parts.joined(separator: " · ") : "\(logicalCores) cores"
    }

    public static func current() -> SystemInfo {
        let logical = Int(Sysctl.integer("hw.logicalcpu") ?? Int64(ProcessInfo.processInfo.activeProcessorCount))
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        let gpu = gpuIdentity()
        return SystemInfo(
            modelName: productName() ?? Sysctl.string("hw.model") ?? "Mac",
            modelIdentifier: Sysctl.string("hw.model") ?? "",
            chip: Sysctl.string("machdep.cpu.brand_string") ?? "Apple Silicon",
            osVersion: "macOS \(version)",
            osBuild: Sysctl.string("kern.osversion") ?? "",
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            physicalMemory: UInt64(Sysctl.integer("hw.memsize") ?? 0),
            logicalCores: logical,
            clusters: clusters(logical: logical),
            gpuName: gpu.name,
            gpuCores: gpu.cores,
            gpuWorkingSet: MTLCreateSystemDefaultDevice().map { UInt64($0.recommendedMaxWorkingSetSize) } ?? 0,
            bootTime: bootTime()
        )
    }

    private static func productName() -> String? {
        var name: String?
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if root != 0 {
            name = IOReg.string(IOReg.property(root, "product-name"))
            IOObjectRelease(root)
        }
        return name
    }

    private static func bootTime() -> Date {
        guard let tv = Sysctl.raw("kern.boottime", as: timeval.self, initial: timeval()) else { return Date() }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    private static func gpuIdentity() -> (name: String, cores: Int?) {
        var name: String?
        var cores: Int?
        IOReg.forEachService(matching: "IOAccelerator") { entry in
            guard name == nil else { return }
            name = IOReg.string(IOReg.property(entry, "model"))
            cores = IOReg.int(IOReg.property(entry, "gpu-core-count"))
        }
        return (name ?? MTLCreateSystemDefaultDevice()?.name ?? "GPU", cores)
    }

    /// Groups logical CPUs into clusters ("Super", "Performance", "Efficiency"...).
    ///
    /// The device tree tags each CPU with a cluster type letter; sysctl's perflevels carry
    /// the human names and core counts. They are matched on core count because the letters
    /// differ between chip generations.
    static func clusters(logical: Int) -> [CoreCluster] {
        var typeByCPU: [Int: String] = [:]
        IOReg.forEachChild(ofPath: "IODeviceTree:/cpus", plane: "IODeviceTree") { cpu in
            if let id = IOReg.int(IOReg.property(cpu, "logical-cpu-id")),
               let type = IOReg.string(IOReg.property(cpu, "cluster-type")) {
                typeByCPU[id] = type
            }
        }
        let levels = Int(Sysctl.integer("hw.nperflevels") ?? 0)
        let perf: [(name: String, count: Int)] = (0..<levels).compactMap { i in
            guard let count = Sysctl.integer("hw.perflevel\(i).logicalcpu") else { return nil }
            return (Sysctl.string("hw.perflevel\(i).name") ?? "Level \(i)", Int(count))
        }
        guard perf.count > 1 else { return [CoreCluster(name: "Cores", cores: Array(0..<logical))] }

        var groups = Dictionary(grouping: typeByCPU.keys.sorted()) { typeByCPU[$0]! }
        var result: [CoreCluster] = []
        for level in perf {
            if let match = groups.first(where: { $0.value.count == level.count }) {
                result.append(CoreCluster(name: level.name, cores: match.value.sorted()))
                groups.removeValue(forKey: match.key)
            }
        }
        if result.count == perf.count { return result }

        // No device-tree data: Apple orders the slowest cores first.
        var next = 0
        var fallback: [CoreCluster] = []
        for level in perf.reversed() {
            let range = Array(next..<min(logical, next + level.count))
            next += level.count
            fallback.insert(CoreCluster(name: level.name, cores: range), at: 0)
        }
        return fallback
    }
}
