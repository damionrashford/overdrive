import OverdriveCore
import SwiftUI

struct BatteryPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let p = store.power
        let range = store.settings.chartRange
        PageScaffold(page: .battery, subtitle: subtitle) {
            HStack(spacing: 8) {
                if p.lowPowerMode { Pill(text: "Low Power Mode", color: Theme.warn, symbol: "leaf.fill") }
                Pill(text: p.onAC ? (p.isCharging ? "Charging" : "On power") : "On battery",
                     color: p.onAC ? Theme.good : Theme.secondary, symbol: p.onAC ? "powerplug.fill" : "battery.50percent")
            }
        } content: {
            if !p.hasBattery {
                Card { EmptyHint(symbol: "powerplug", title: "No battery", detail: "This Mac runs on mains power.") }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        CardHeader(title: "Charge", symbol: "battery.100percent", colors: Theme.battery)
                        RingGauge(value: p.percent, colors: p.percent < 0.2 && !p.onAC ? Theme.danger : Theme.battery, lineWidth: 14, label: "Battery charge") {
                            VStack(spacing: 0) {
                                BigNumber(value: String(format: "%.0f", p.percent * 100), unit: "%", size: 40)
                                Text(timeText).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .frame(width: 168, height: 168)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 14)
                        HStack(alignment: .top) {
                            StatTile(label: "Power", value: p.batteryWatts.map { Fmt.watts(abs($0)) } ?? "–",
                                     caption: (p.batteryWatts ?? 0) >= 0 ? "into the battery" : "drawn from battery")
                            StatTile(label: "Voltage", value: p.voltage.map { String(format: "%.2f V", $0) } ?? "–")
                        }
                    }
                    .frame(width: 290)

                    Card {
                        CardHeader(title: "Health", subtitle: "From the battery controller", symbol: "heart.text.square", colors: Theme.battery)
                        HStack(alignment: .top) {
                            StatTile(label: "Maximum capacity", value: p.health.map { Fmt.percent($0) } ?? "–",
                                     caption: "of design capacity", tint: (p.health ?? 1) < 0.8 ? Theme.warn : Theme.text)
                            StatTile(label: "Cycle count", value: p.cycleCount.map { "\($0)" } ?? "–",
                                     caption: p.designCycleCount.map { "rated for \($0)" })
                            StatTile(label: "Condition", value: p.condition ?? "–", tint: (p.condition ?? "Normal") == "Normal" ? Theme.good : Theme.warn)
                            StatTile(label: "Temperature", value: p.temperatureCelsius.map { store.settings.temperature($0) }
                                     ?? store.sensors.average(.battery).map { store.settings.temperature($0) } ?? "–")
                        }
                        if let cycles = p.cycleCount, let design = p.designCycleCount, design > 0 {
                            SegmentBar(segments: [Segment(id: "cycles", value: Double(cycles), color: Theme.battery[1])],
                                       total: Double(design), height: 8)
                                .padding(.top, 14)
                            Text("\(cycles) of \(design) rated cycles used. Apple considers the battery consumed at 80% capacity.")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary).padding(.top, 6)
                        }
                        Divider().overlay(Theme.hairline).padding(.vertical, 14)
                        HStack(alignment: .top) {
                            StatTile(label: "Adapter", value: p.adapterName ?? (p.onAC ? "Connected" : "None"),
                                     caption: p.adapterWatts.map { "\($0) W" })
                            StatTile(label: "Low Power Mode", value: p.lowPowerMode ? "On" : "Off")
                            StatTile(label: "Time", value: timeText)
                        }
                    }
                }

                Card {
                    HistoryHeader(title: "Charge & Power", colors: Theme.battery) {
                        LegendChip(color: Theme.battery[0], label: "Charge %")
                        LegendChip(color: Theme.gpu[0], label: "Power W")
                    }
                    let watts = store.batteryPower[range]
                    let top = niceCeiling(max(abs(watts.maxValue), abs(watts.points.map(\.value).min() ?? 0)), minimum: 20)
                    LiveChart(series: [
                        ChartSeries(id: "Charge", series: store.batteryLevel[range], color: Theme.battery[0]),
                    ], xDomain: store.batteryLevel[range].xDomain, yMax: 100, height: 150, label: "Charge history")
                    LiveChart(series: [
                        ChartSeries(id: "Power", points: watts.points.map { ChartPoint(id: $0.id, value: abs($0.value)) }, color: Theme.gpu[0]),
                    ], xDomain: watts.xDomain, yMax: top, height: 110, label: "Battery power", format: { Fmt.watts($0) })
                    .padding(.top, 8)
                }

                if !p.peripherals.isEmpty {
                    Card {
                        CardHeader(title: "Bluetooth Devices", subtitle: "Battery levels reported by paired devices", symbol: "keyboard", colors: Theme.battery)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                            ForEach(p.peripherals) { device in
                                HStack(spacing: 12) {
                                    Image(systemName: symbol(for: device.name)).font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.battery[0]).frame(width: 30, height: 30)
                                        .background(Circle().fill(Theme.battery[0].opacity(0.12)))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                        SegmentBar(segments: [Segment(id: "p", value: device.percent, color: device.percent < 0.2 ? Theme.bad : Theme.battery[1])],
                                                   total: 1, height: 6)
                                    }
                                    Text(Fmt.percent(device.percent)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        let p = store.power
        guard p.hasBattery else { return "Mains powered" }
        return "\(p.health.map { "Health \(Fmt.percent($0))" } ?? "")\(p.cycleCount.map { " · \($0) cycles" } ?? "")\(p.adapterName.map { " · \($0)" } ?? "")"
    }

    private var timeText: String {
        let p = store.power
        if p.isCharging, let m = p.minutesToFull { return "\(m / 60)h \(m % 60)m to full" }
        if !p.onAC, let m = p.minutesToEmpty { return "\(m / 60)h \(m % 60)m left" }
        if p.onAC { return p.percent >= 0.99 ? "Fully charged" : "Calculating" }
        return "Calculating"
    }

    private func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("mouse") { return "computermouse" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("airpods") || n.contains("beats") || n.contains("headphone") { return "airpodspro" }
        return "keyboard"
    }
}
