import Foundation
import IOKit
import IOKit.ps

public struct PeripheralBattery: Sendable, Identifiable, Hashable {
    public var id: String { name + address }
    public let name: String
    public let address: String
    public let percent: Double
}

public struct PowerSnapshot: Sendable {
    public var hasBattery = false
    public var percent: Double = 0
    public var isCharging = false
    public var onAC = false
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var cycleCount: Int?
    public var designCycleCount: Int?
    /// Current full-charge capacity against design capacity, 0...1.
    public var health: Double?
    public var condition: String?
    /// Instantaneous battery power in watts: positive while charging, negative while discharging.
    public var batteryWatts: Double?
    public var voltage: Double?
    public var temperatureCelsius: Double?
    public var adapterName: String?
    public var adapterWatts: Int?
    public var lowPowerMode = false
    public var peripherals: [PeripheralBattery] = []

    public init() {}
}

public final class PowerSampler {
    private var slowAt: Double = -.infinity
    private var slow: (cycles: Int?, designCycles: Int?, health: Double?, condition: String?, adapterName: String?, adapterWatts: Int?)
        = (nil, nil, nil, nil, nil, nil)
    private var peripheralsAt: Double = -.infinity
    private var peripherals: [PeripheralBattery] = []

    public init() {}

    public func sample() -> PowerSnapshot {
        var snap = PowerSnapshot()
        snap.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let now = monotonicSeconds()
        if now - peripheralsAt > 30 {
            peripherals = Self.readPeripherals()
            peripheralsAt = now
        }
        snap.peripherals = peripherals

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
            if let c = d["BatteryHealthCondition"] as? String { snap.condition = c }
        }
        guard snap.hasBattery else { return snap }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return snap }
        defer { IOObjectRelease(service) }

        // Voltage is reported in mV and amperage in mA (negative while discharging).
        if let mv = IOReg.int(IOReg.property(service, "Voltage")), let ma = IOReg.int(IOReg.property(service, "InstantAmperage")) {
            let amps = Double(Int64(truncatingIfNeeded: ma))
            snap.voltage = Double(mv) / 1000
            snap.batteryWatts = Double(mv) / 1000 * amps / 1000
        }
        if let t = IOReg.int(IOReg.property(service, "Temperature")) {
            snap.temperatureCelsius = Double(t) / 100
        } else if let t = IOReg.int(IOReg.property(service, "VirtualTemperature")) {
            snap.temperatureCelsius = Double(t) / 100
        }
        if now - slowAt > 300 {
            slow.cycles = IOReg.int(IOReg.property(service, "CycleCount"))
            slow.designCycles = IOReg.int(IOReg.property(service, "DesignCycleCount9C"))
            let data = IOReg.property(service, "BatteryData") as? [String: Any]
            let design = IOReg.int(data?["DesignCapacity"]) ?? IOReg.int(IOReg.property(service, "DesignCapacity"))
            let full = IOReg.int(data?["NominalChargeCapacity"])
                ?? IOReg.int(IOReg.property(service, "NominalChargeCapacity"))
                ?? IOReg.int(IOReg.property(service, "AppleRawMaxCapacity"))
            if let design, let full, design > 0 { slow.health = min(1, Double(full) / Double(design)) }
            if let adapter = IOReg.property(service, "AdapterDetails") as? [String: Any] {
                slow.adapterName = (adapter["Name"] as? String)?.trimmingCharacters(in: .whitespaces)
                    ?? (adapter["Description"] as? String)
                slow.adapterWatts = IOReg.int(adapter["Watts"])
            } else {
                slow.adapterName = nil
                slow.adapterWatts = nil
            }
            slowAt = now
        }
        snap.cycleCount = slow.cycles
        snap.designCycleCount = slow.designCycles
        snap.health = slow.health
        if snap.condition == nil, let h = slow.health {
            snap.condition = h >= 0.8 ? "Normal" : "Service Recommended"
        }
        if snap.onAC {
            snap.adapterName = slow.adapterName
            snap.adapterWatts = slow.adapterWatts
        }
        return snap
    }

    /// Bluetooth mice, keyboards and headphones publish their charge in the IORegistry.
    static func readPeripherals() -> [PeripheralBattery] {
        var found: [PeripheralBattery] = []
        for className in ["AppleDeviceManagementHIDEventService", "BNBMouseDevice", "AppleHSBluetoothDevice", "IOBluetoothHostControllerUSBTransport"] {
            IOReg.forEachService(matching: className) { entry in
                guard let percent = IOReg.int(IOReg.property(entry, "BatteryPercent")),
                      let name = IOReg.string(IOReg.property(entry, "Product")) else { return }
                let transport = IOReg.string(IOReg.property(entry, "Transport")) ?? ""
                guard transport != "FIFO" else { return }  // built-in keyboard/trackpad has no battery of its own
                let address = IOReg.string(IOReg.property(entry, "DeviceAddress")) ?? ""
                if !found.contains(where: { $0.name == name && $0.address == address }) {
                    found.append(PeripheralBattery(name: name, address: address, percent: Double(percent) / 100))
                }
            }
        }
        return found
    }
}
