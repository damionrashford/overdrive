import Foundation
import IOKit

public struct GPUSnapshot: Sendable {
    public var available = false
    /// All three are 0...1.
    public var device: Double = 0
    public var renderer: Double = 0
    public var tiler: Double = 0
    public var inUseMemory: UInt64 = 0
    public var allocatedMemory: UInt64 = 0

    public init() {}
}

/// Reads the accelerator's PerformanceStatistics, the same counters Activity Monitor's GPU history uses.
public final class GPUSampler {
    public init() {}

    public func sample() -> GPUSnapshot {
        var snap = GPUSnapshot()
        IOReg.forEachService(matching: "IOAccelerator") { entry in
            guard !snap.available,
                  let stats = IOReg.property(entry, "PerformanceStatistics") as? [String: Any] else { return }
            snap.available = true
            snap.device = percent(stats["Device Utilization %"])
            snap.renderer = percent(stats["Renderer Utilization %"])
            snap.tiler = percent(stats["Tiler Utilization %"])
            snap.inUseMemory = IOReg.uint64(stats["In use system memory"])
            snap.allocatedMemory = IOReg.uint64(stats["Alloc system memory"])
        }
        return snap
    }

    private func percent(_ value: Any?) -> Double {
        let raw = (value as? NSNumber)?.doubleValue ?? 0
        return max(0, min(1, raw / 100))
    }
}
