import OverdriveCore
import SwiftUI

struct SensorsPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let s = store.sensors
        let range = store.settings.chartRange
        PageScaffold(page: .sensors, subtitle: "\(s.temperatures.count) temperature sensors · \(s.fans.count) fan\(s.fans.count == 1 ? "" : "s") · read from the SMC") {
            HStack(spacing: 8) {
                if let w = s.systemPower { Pill(text: "\(Fmt.watts(w)) total", color: Theme.secondary, symbol: "bolt") }
                Pill(text: "Thermal: \(store.thermalLabel)", color: store.thermalColor, symbol: "flame")
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                TempRing(title: "CPU", value: s.average(.cpu), peak: s.hottest(.cpu))
                TempRing(title: "GPU", value: s.average(.gpu), peak: s.hottest(.gpu))
                ForEach(s.fans) { fan in
                    Card {
                        CardHeader(title: s.fans.count == 1 ? "Fan" : "Fan \(fan.id + 1)", symbol: "fanblades", colors: Theme.sensors)
                        RingGauge(value: fan.fraction, colors: Theme.cpu, lineWidth: 12, label: "Fan \(fan.id + 1) speed") {
                            VStack(spacing: 0) {
                                Text(String(format: "%.0f", fan.rpm)).font(Theme.rounded(26, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                                Text("rpm").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .frame(width: 128, height: 128)
                        .frame(maxWidth: .infinity)
                        Text("\(Fmt.rpm(fan.minimum)) – \(Fmt.rpm(fan.maximum)) · target \(Fmt.rpm(fan.target))")
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
                    }
                }
            }

            Card {
                HistoryHeader(title: "Temperatures", colors: Theme.sensors) {
                    LegendChip(color: Theme.sensors[0], label: "CPU")
                    LegendChip(color: Theme.gpu[0], label: "GPU")
                }
                LiveChart(series: [
                    ChartSeries(id: "CPU", series: store.cpuTemperature[range], color: Theme.sensors[0]),
                    ChartSeries(id: "GPU", series: store.gpuTemperature[range], color: Theme.gpu[0], fill: false),
                ], xDomain: store.cpuTemperature[range].xDomain, yMax: 120, height: 190, label: "Temperature history",
                          format: { store.settings.temperature($0) })
            }

            HStack(alignment: .top, spacing: 16) {
                Card {
                    HistoryHeader(title: "Power", subtitle: "Package power from the SMC", colors: Theme.gpu)
                    let top = niceCeiling(store.systemPower[range].maxValue, minimum: 20)
                    LiveChart(series: [ChartSeries(id: "System", series: store.systemPower[range], color: Theme.gpu[0])],
                              xDomain: store.systemPower[range].xDomain, yMax: top, height: 120, label: "Power history", format: { Fmt.watts($0) })
                    Divider().overlay(Theme.hairline).padding(.vertical, 12)
                    HStack(alignment: .top) {
                        ForEach(s.power) { reading in
                            StatTile(label: reading.name, value: Fmt.watts(reading.watts))
                        }
                    }
                }
                Card {
                    CardHeader(title: "All Sensors", subtitle: "Grouped by component", symbol: "list.bullet", colors: Theme.sensors)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(SensorGroup.allCases, id: \.self) { group in
                            let readings = s.temperatures.filter { $0.group == group }
                            if !readings.isEmpty {
                                Section {
                                    ForEach(readings) { r in
                                        HStack {
                                            Text(r.name).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                                            Spacer()
                                            Text(store.settings.temperature(r.value)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                                                .foregroundStyle(Theme.thermal(r.value))
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                } header: {
                                    Text(group.rawValue.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6)
                                        .foregroundStyle(Theme.tertiary).padding(.top, 8)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct TempRing: View {
        @Environment(MonitorStore.self) private var store
        let title: String
        let value: Double?
        let peak: Double?

        var body: some View {
            Card {
                CardHeader(title: "\(title) Temperature", symbol: "thermometer.medium", colors: Theme.sensors)
                let t = value ?? 0
                RingGauge(value: min(1, t / 110), colors: [Theme.thermal(t), Theme.thermal(t)], lineWidth: 12, label: "\(title) temperature") {
                    VStack(spacing: 0) {
                        Text(value.map { store.settings.temperature($0) } ?? "–").font(Theme.rounded(26, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                        Text("average").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(width: 128, height: 128)
                .frame(maxWidth: .infinity)
                Text(peak.map { "hottest \(store.settings.temperature($0))" } ?? "no sensor")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
            }
        }
    }
}
