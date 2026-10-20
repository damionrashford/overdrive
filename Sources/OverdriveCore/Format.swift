import Foundation

public enum Fmt {
    /// Binary units, matching Activity Monitor for memory.
    public static func memory(_ bytes: UInt64) -> String { scaled(Double(bytes), base: 1024) }

    /// Decimal units, matching Finder for storage.
    public static func storage(_ bytes: UInt64) -> String { scaled(Double(bytes), base: 1000) }

    public static func rate(_ bytesPerSecond: Double) -> String { scaled(max(0, bytesPerSecond), base: 1000) + "/s" }

    public static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", fraction * 100)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400, hours = (total % 86_400) / 3600, minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func scaled(_ value: Double, base: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = value
        var i = 0
        while v >= base && i < units.count - 1 {
            v /= base
            i += 1
        }
        if i == 0 { return "\(Int(v)) B" }
        let digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2)
        return String(format: "%.\(digits)f %@", v, units[i])
    }
}

public enum Paths {
    /// The folder cleanup, uninstall and large-file scans work in: the person's real home folder,
    /// or in the App Sandbox the folder they granted. `OVERDRIVE_HOME` points it at a scratch folder
    /// so the clean and trash flows can be exercised end to end without touching real data.
    nonisolated(unsafe) public static var home: URL = {
        if let override = ProcessInfo.processInfo.environment["OVERDRIVE_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Capabilities.current.realHome
    }()

    public static var isOverridden: Bool { ProcessInfo.processInfo.environment["OVERDRIVE_HOME"] != nil }

    public static func temperature(_ celsius: Double, fahrenheit: Bool = false) -> String {
        fahrenheit ? String(format: "%.0f°F", celsius * 9 / 5 + 32) : String(format: "%.0f°C", celsius)
    }
}

public extension Fmt {
    static func watts(_ w: Double) -> String { abs(w) >= 10 ? String(format: "%.0f W", w) : String(format: "%.1f W", w) }
    static func rpm(_ v: Double) -> String { String(format: "%.0f rpm", v) }
}
