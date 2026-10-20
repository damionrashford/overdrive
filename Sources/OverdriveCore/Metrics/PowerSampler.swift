import Foundation
import IOKit
import IOKit.ps

public struct PowerSnapshot: Sendable {
    public var hasBattery = false
    public var percent: Double = 0
    public var isCharging = false
    public var onAC = false
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var cycleCount: Int?
    /// Current full-charge capacity against design capacity, 0...1.
    public var health: Double?

    public init() {}
}

public final class PowerSampler {
    private var batteryDetails: (cycles: Int?, health: Double?, at: Double) = (nil, nil, -.infinity)

    public init() {}

    public func sample() -> PowerSnapshot {
        var snap = PowerSnapshot()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return snap }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d["Type"] as? String) == "InternalBattery" else { continue }
            snap.hasBattery = true
            let current = (d["Current Capacity"] as? NSNumber)?.doubleValue ?? 0
            let max = (d["Max Capacity"] as? NSNumber)?.doubleValue ?? 100
            snap.percent = max > 0 ? min(1, current / max) : 0
            snap.isCharging = (d["Is Charging"] as? Bool) ?? false
            snap.onAC = (d["Power Source State"] as? String) == "AC Power"
            if let t = (d["Time to Empty"] as? NSNumber)?.intValue, t > 0, !snap.onAC { snap.minutesToEmpty = t }
            if let t = (d["Time to Full Charge"] as? NSNumber)?.intValue, t > 0, snap.isCharging { snap.minutesToFull = t }
        }
        if snap.hasBattery {
            let now = monotonicSeconds()
            if now - batteryDetails.at > 300 { batteryDetails = Self.readBatteryDetails(at: now) }
            snap.cycleCount = batteryDetails.cycles
            snap.health = batteryDetails.health
        }
        return snap
    }

    private static func readBatteryDetails(at time: Double) -> (Int?, Double?, Double) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil, time) }
        defer { IOObjectRelease(service) }
        let cycles = IOReg.int(IOReg.property(service, "CycleCount"))
        var health: Double?
        let data = IOReg.property(service, "BatteryData") as? [String: Any]
        let design = IOReg.int(data?["DesignCapacity"]) ?? IOReg.int(IOReg.property(service, "DesignCapacity"))
        let full = IOReg.int(data?["NominalChargeCapacity"])
            ?? IOReg.int(IOReg.property(service, "NominalChargeCapacity"))
            ?? IOReg.int(IOReg.property(service, "AppleRawMaxCapacity"))
        if let design, let full, design > 0 { health = min(1, Double(full) / Double(design)) }
        return (cycles, health, time)
    }
}
