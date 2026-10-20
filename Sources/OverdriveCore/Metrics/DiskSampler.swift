import Foundation
import IOKit

public struct DiskIOSnapshot: Sendable {
    public var readPerSec: Double = 0
    public var writePerSec: Double = 0
    public var readOpsPerSec: Double = 0
    public var writeOpsPerSec: Double = 0
    public var totalRead: UInt64 = 0
    public var totalWritten: UInt64 = 0

    public init() {}
}

public struct VolumeInfo: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let format: String
    public let total: UInt64
    /// Free right now.
    public let free: UInt64
    /// Free once macOS evicts purgeable data (what Finder reports as "available").
    public let available: UInt64
    public let isRoot: Bool
    public let isInternal: Bool
    public let isRemovable: Bool

    public var purgeable: UInt64 { available > free ? available - free : 0 }
    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    public var availableFraction: Double { total == 0 ? 0 : Double(available) / Double(total) }
}

public final class DiskSampler {
    private var previous: (time: Double, read: UInt64, written: UInt64, readOps: UInt64, writeOps: UInt64)?

    public init() {}

    public func sampleIO() -> DiskIOSnapshot {
        var read: UInt64 = 0, written: UInt64 = 0, readOps: UInt64 = 0, writeOps: UInt64 = 0
        IOReg.forEachService(matching: "IOBlockStorageDriver") { entry in
            guard let stats = IOReg.property(entry, "Statistics") as? [String: Any] else { return }
            read += IOReg.uint64(stats["Bytes (Read)"])
            written += IOReg.uint64(stats["Bytes (Write)"])
            readOps += IOReg.uint64(stats["Operations (Read)"])
            writeOps += IOReg.uint64(stats["Operations (Write)"])
        }
        var snap = DiskIOSnapshot()
        snap.totalRead = read
        snap.totalWritten = written
        let now = monotonicSeconds()
        if let p = previous, now > p.time {
            let dt = now - p.time
            snap.readPerSec = Double(positiveDelta(read, p.read)) / dt
            snap.writePerSec = Double(positiveDelta(written, p.written)) / dt
            snap.readOpsPerSec = Double(positiveDelta(readOps, p.readOps)) / dt
            snap.writeOpsPerSec = Double(positiveDelta(writeOps, p.writeOps)) / dt
        }
        previous = (now, read, written, readOps, writeOps)
        return snap
    }

    public static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
            .volumeIsInternalKey, .volumeIsRemovableKey, .volumeLocalizedFormatDescriptionKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let volumes: [VolumeInfo] = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal == true,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let free = UInt64(max(0, v.volumeAvailableCapacity ?? 0))
            let important = v.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? free
            return VolumeInfo(
                name: v.volumeName ?? url.lastPathComponent,
                path: url.path,
                format: v.volumeLocalizedFormatDescription ?? "",
                total: UInt64(total),
                free: free,
                available: max(free, important),
                isRoot: v.volumeIsRootFileSystem ?? false,
                isInternal: v.volumeIsInternal ?? false,
                isRemovable: v.volumeIsRemovable ?? false
            )
        }
        return volumes.sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
    }
}
