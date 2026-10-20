import Foundation
import Observation
import OverdriveCore

enum ChartRange: String, CaseIterable, Identifiable {
    case live, hour, day
    var id: String { rawValue }
    var label: String {
        switch self {
        case .live: "3 min"
        case .hour: "1 hour"
        case .day: "24 hours"
        }
    }
}

enum MenuBarModule: String, CaseIterable, Identifiable, Codable {
    case cpu, memory, network, temperature
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .temperature: "CPU temperature"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, text, graph
    var id: String { rawValue }
    var label: String {
        switch self {
        case .icon: "Icon only"
        case .text: "Values"
        case .graph: "Graphs"
        }
    }
}

/// Every persisted preference, in one place. Values are read once and written through.
@MainActor @Observable
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshInterval = defaults.object(forKey: "refreshInterval") as? Double ?? 2
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .text
        menuBarModules = Self.decode(defaults.data(forKey: "menuBarModules")) ?? [.cpu, .memory]
        useFahrenheit = defaults.bool(forKey: "useFahrenheit")
        chartRange = ChartRange(rawValue: defaults.string(forKey: "chartRange") ?? "") ?? .live
        cleanupExclusions = Set(defaults.stringArray(forKey: "cleanupExclusions") ?? [])
        showPublicIP = defaults.bool(forKey: "showPublicIP")
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
        alertRules = Self.decode(defaults.data(forKey: "alertRules")) ?? AlertRule.defaults
    }

    var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    var menuBarModules: [MenuBarModule] { didSet { defaults.set(Self.encode(menuBarModules), forKey: "menuBarModules") } }
    var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: "useFahrenheit") } }
    var chartRange: ChartRange { didSet { defaults.set(chartRange.rawValue, forKey: "chartRange") } }
    /// Cleanup entries (by path) the person told us to leave alone.
    var cleanupExclusions: Set<String> { didSet { defaults.set(Array(cleanupExclusions).sorted(), forKey: "cleanupExclusions") } }
    var showPublicIP: Bool { didSet { defaults.set(showPublicIP, forKey: "showPublicIP") } }
    var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }
    var alertRules: [AlertRule] { didSet { defaults.set(Self.encode(alertRules), forKey: "alertRules") } }

    func rule(_ kind: AlertKind) -> AlertRule {
        alertRules.first { $0.kind == kind } ?? AlertRule.defaults.first { $0.kind == kind }!
    }

    func update(_ rule: AlertRule) {
        if let i = alertRules.firstIndex(where: { $0.kind == rule.kind }) { alertRules[i] = rule } else { alertRules.append(rule) }
    }

    func temperature(_ celsius: Double) -> String { Paths.temperature(celsius, fahrenheit: useFahrenheit) }

    private static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    private static func decode<T: Decodable>(_ data: Data?) -> T? { data.flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
}

private extension UInt64 {
    var nonZero: UInt64? { self == 0 ? nil : self }
}

enum AlertKind: String, CaseIterable, Codable, Identifiable {
    case cpu, memoryPressure, diskSpace, temperature, battery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU stays busy"
        case .memoryPressure: "Memory pressure"
        case .diskSpace: "Low disk space"
        case .temperature: "CPU temperature"
        case .battery: "Battery low"
        }
    }

    var detail: String {
        switch self {
        case .cpu: "Total CPU above the threshold for the whole duration."
        case .memoryPressure: "macOS reports elevated or critical memory pressure."
        case .diskSpace: "Startup disk drops below the threshold."
        case .temperature: "Average CPU temperature above the threshold (direct edition)."
        case .battery: "Charge falls below the threshold while on battery."
        }
    }

    var unit: String {
        switch self {
        case .cpu: "%"
        case .memoryPressure: ""
        case .diskSpace: "GB"
        case .temperature: "°C"
        case .battery: "%"
        }
    }

    var hasThreshold: Bool { self != .memoryPressure }
    var hasDuration: Bool { self == .cpu || self == .temperature }
    var thresholdRange: ClosedRange<Double> {
        switch self {
        case .cpu: 50...100
        case .memoryPressure: 0...0
        case .diskSpace: 5...200
        case .temperature: 60...105
        case .battery: 5...50
        }
    }
    var step: Double { self == .diskSpace ? 5 : 5 }
}

struct AlertRule: Codable, Identifiable, Hashable {
    var id: String { kind.rawValue }
    let kind: AlertKind
    var enabled: Bool
    var threshold: Double
    var sustainedSeconds: Double

    static let defaults: [AlertRule] = [
        AlertRule(kind: .cpu, enabled: false, threshold: 90, sustainedSeconds: 120),
        AlertRule(kind: .memoryPressure, enabled: true, threshold: 0, sustainedSeconds: 0),
        AlertRule(kind: .diskSpace, enabled: true, threshold: 20, sustainedSeconds: 0),
        AlertRule(kind: .temperature, enabled: false, threshold: 95, sustainedSeconds: 60),
        AlertRule(kind: .battery, enabled: false, threshold: 15, sustainedSeconds: 0),
    ]
}
