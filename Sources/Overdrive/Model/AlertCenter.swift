import Foundation
import Observation
import OverdriveCore
import UserNotifications

/// Evaluates alert rules on every sample and posts local notifications, with a cooldown per rule so
/// a bad hour does not become fifty banners.
@MainActor @Observable
final class AlertCenter {
    enum Authorization { case unknown, granted, denied }

    var authorization: Authorization = .unknown
    /// Rules currently over their threshold (for the "firing" badge in Settings and the Overview).
    private(set) var active: Set<AlertKind> = []
    private(set) var lastFired: [AlertKind: Date] = [:]

    @ObservationIgnored private var since: [AlertKind: Date] = [:]
    @ObservationIgnored private let cooldown: TimeInterval = 15 * 60

    /// Notifications need a real bundle; the bare test binary has none.
    private static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func refreshAuthorization() {
        guard Self.canNotify else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional: self.authorization = .granted
                case .denied: self.authorization = .denied
                default: self.authorization = .unknown
                }
            }
        }
    }

    func requestAuthorization() {
        guard Self.canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorization = granted ? .granted : .denied }
        }
    }

    func evaluate(store: MonitorStore, settings: AppSettings, now: Date = Date()) {
        for rule in settings.alertRules {
            let over = isOver(rule, store: store)
            guard rule.enabled, over else {
                since[rule.kind] = nil
                active.remove(rule.kind)
                continue
            }
            let start = since[rule.kind] ?? now
            since[rule.kind] = start
            guard now.timeIntervalSince(start) >= rule.sustainedSeconds else { continue }
            active.insert(rule.kind)
            if let last = lastFired[rule.kind], now.timeIntervalSince(last) < cooldown { continue }
            lastFired[rule.kind] = now
            post(rule, store: store, settings: settings)
        }
    }

    private func isOver(_ rule: AlertRule, store: MonitorStore) -> Bool {
        switch rule.kind {
        case .cpu: return store.cpu.total * 100 >= rule.threshold
        case .memoryPressure: return store.memory.pressure != .normal
        case .diskSpace:
            guard let root = store.rootVolume else { return false }
            return Double(root.available) < rule.threshold * 1_000_000_000
        case .temperature:
            guard let t = store.sensors.average(.cpu) else { return false }
            return t >= rule.threshold
        case .battery:
            return store.power.hasBattery && !store.power.onAC && store.power.percent * 100 <= rule.threshold
        }
    }

    private func post(_ rule: AlertRule, store: MonitorStore, settings: AppSettings) {
        guard Self.canNotify, authorization == .granted else { return }
        let content = UNMutableNotificationContent()
        switch rule.kind {
        case .cpu:
            content.title = "CPU has been busy for \(Int(rule.sustainedSeconds / 60)) min"
            let top = store.top(by: \.cpu, limit: 1).first
            content.body = top.map { "\($0.name) is using \(Int($0.cpu))% CPU." } ?? "Total CPU is at \(Fmt.percent(store.cpu.total))."
        case .memoryPressure:
            content.title = "Memory pressure is \(store.memory.pressure.label.lowercased())"
            let top = store.topByMemory(limit: 1).first
            content.body = top.map { "\($0.name) is using \(Fmt.memory($0.memory)). Quitting it would help." } ?? "macOS is compressing and swapping memory."
        case .diskSpace:
            content.title = "Startup disk is almost full"
            content.body = "\(Fmt.storage(store.rootVolume?.available ?? 0)) left. Open Cleanup to free space."
        case .temperature:
            content.title = "CPU is running hot"
            content.body = "Average CPU temperature is \(settings.temperature(store.sensors.average(.cpu) ?? 0))."
        case .battery:
            content.title = "Battery at \(Fmt.percent(store.power.percent))"
            content.body = store.power.minutesToEmpty.map { "About \($0) minutes left." } ?? "Connect to power soon."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "overdrive.\(rule.kind.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
