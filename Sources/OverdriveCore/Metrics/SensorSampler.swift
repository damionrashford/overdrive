import Foundation

public enum SensorGroup: String, Sendable, CaseIterable {
    case cpu = "CPU", gpu = "GPU", memory = "Memory", battery = "Battery", storage = "Storage", system = "System"
}

public struct SensorReading: Sendable, Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let group: SensorGroup
    /// Degrees Celsius.
    public let value: Double
}

public struct FanReading: Sendable, Identifiable, Hashable {
    public let id: Int
    public let rpm: Double
    public let minimum: Double
    public let maximum: Double
    public let target: Double

    public var fraction: Double { maximum > minimum ? max(0, min(1, (rpm - minimum) / (maximum - minimum))) : 0 }
}

public struct PowerReading: Sendable, Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let name: String
    /// Watts.
    public let watts: Double
}

public struct SensorSnapshot: Sendable {
    public var available = false
    public var temperatures: [SensorReading] = []
    public var fans: [FanReading] = []
    public var power: [PowerReading] = []

    public func average(_ group: SensorGroup) -> Double? {
        let values = temperatures.filter { $0.group == group }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    public func hottest(_ group: SensorGroup) -> Double? {
        temperatures.filter { $0.group == group }.map(\.value).max()
    }

    public var systemPower: Double? { power.first { $0.key == "PSTR" }?.watts }

    public init() {}
}

/// Resolves SMC keys to readable sensor names. Core-temperature keys differ by chip generation
/// (the table follows the community-maintained map used by Stats and iStat-style tools);
/// anything else that looks like a temperature is still shown, grouped by its first letters.
public final class SensorSampler {
    private let reader: SMCReader?
    private var catalog: [(key: String, name: String, group: SensorGroup)] = []
    private var fanCount = 0
    private var powerKeys: [(key: String, name: String)] = []
    private var discovered = false

    public init(chip: String) {
        reader = SMCReader()
        if reader != nil { discover(chip: chip) }
    }

    public var isAvailable: Bool { reader != nil && !catalog.isEmpty }

    public func sample() -> SensorSnapshot {
        var snap = SensorSnapshot()
        guard let reader, discovered else { return snap }
        snap.available = true
        for entry in catalog {
            guard let v = reader.readFloat(entry.key), v > 0, v < 130 else { continue }
            snap.temperatures.append(SensorReading(key: entry.key, name: entry.name, group: entry.group, value: v))
        }
        for i in 0..<fanCount {
            guard let rpm = reader.readFloat("F\(i)Ac") else { continue }
            snap.fans.append(FanReading(id: i, rpm: rpm,
                                        minimum: reader.readFloat("F\(i)Mn") ?? 0,
                                        maximum: reader.readFloat("F\(i)Mx") ?? max(rpm, 1),
                                        target: reader.readFloat("F\(i)Tg") ?? rpm))
        }
        for p in powerKeys {
            if let w = reader.readFloat(p.key), w >= 0, w < 1000 { snap.power.append(PowerReading(key: p.key, name: p.name, watts: w)) }
        }
        return snap
    }

    private func discover(chip: String) {
        guard let reader else { return }
        let present = Set(reader.allKeys().map(\.name))
        let generation = Self.generation(of: chip)
        var entries: [(String, String, SensorGroup)] = []

        func add(_ keys: [String], _ label: String, _ group: SensorGroup) {
            var n = 0
            for key in keys where present.contains(key) {
                n += 1
                entries.append((key, keys.count > 1 ? "\(label) \(n)" : label, group))
            }
        }

        switch generation {
        case 1:
            add(["Tp09", "Tp0T"], "Efficiency core", .cpu)
            add(["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"], "Performance core", .cpu)
            add(["Tg05", "Tg0D", "Tg0L", "Tg0T"], "GPU cluster", .gpu)
            add(["Tm02", "Tm06", "Tm08", "Tm09"], "Memory", .memory)
        case 2:
            add(["Tp1h", "Tp1t", "Tp1p", "Tp1l"], "Efficiency core", .cpu)
            add(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"], "Performance core", .cpu)
            add(["Tg0f", "Tg0j"], "GPU cluster", .gpu)
        case 3:
            add(["Te05", "Te0L", "Te0P", "Te0S"], "Efficiency core", .cpu)
            add(["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"], "Performance core", .cpu)
            add(["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"], "GPU cluster", .gpu)
        case 4:
            add(["Te05", "Te0S", "Te09", "Te0H"], "Efficiency core", .cpu)
            add(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"], "Performance core", .cpu)
            add(["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"], "GPU cluster", .gpu)
            add(["Tm0p", "Tm1p", "Tm2p"], "Memory", .memory)
        case 5:
            add(["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"], "Super core", .cpu)
            add(["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"], "Performance core", .cpu)
            add(["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"], "GPU cluster", .gpu)
        default:
            add(["TC0D", "TC0E", "TC0F", "TC0P", "TCAD"], "CPU", .cpu)
            add(["TG0D", "TG0H", "TG0P"], "GPU", .gpu)
        }
        add(["TB0T", "TB1T", "TB2T"], "Battery cell", .battery)
        add(["TH0a", "TH0b", "TH0x"], "SSD", .storage)
        add(["TW0P"], "Wi‑Fi module", .system)
        add(["TaLP", "TaRF", "TAOL"], "Airflow", .system)
        add(["Ts0P", "Ts1P"], "Palm rest", .system)
        add(["TCHP", "TCMb"], "Charger", .system)
        catalog = entries.map { (key: $0.0, name: $0.1, group: $0.2) }

        fanCount = Int(reader.readFloat("FNum") ?? 0)
        if fanCount == 0 { fanCount = (0..<4).filter { present.contains("F\($0)Ac") }.count }

        powerKeys = [("PSTR", "System total"), ("PDTR", "DC input"), ("PPBR", "Battery"), ("PCPC", "CPU package"),
                     ("PCTR", "CPU total"), ("PGTR", "GPU total"), ("PG0R", "GPU")]
            .filter { present.contains($0.0) }
            .map { (key: $0.0, name: $0.1) }
        discovered = true
    }

    static func generation(of chip: String) -> Int {
        guard let range = chip.range(of: #"M(\d)"#, options: .regularExpression) else { return 0 }
        return Int(chip[range].dropFirst()) ?? 0
    }
}
