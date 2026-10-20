import OverdriveCore
import SwiftUI

struct CPUPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let range = store.settings.chartRange
        PageScaffold(page: .cpu, subtitle: "\(store.info.chip) · \(store.info.coreSummary)") {
            HStack(spacing: 8) {
                if let t = store.sensors.average(.cpu) {
                    Pill(text: store.settings.temperature(t), color: Theme.thermal(t), symbol: "thermometer.medium")
                }
                Pill(text: "Thermal: \(store.thermalLabel)", color: store.thermalColor, symbol: "flame")
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Utilization", symbol: "gauge.with.dots.needle.67percent", colors: Theme.cpu)
                    RingGauge(value: store.cpu.total, colors: Theme.cpu, lineWidth: 14, label: "CPU utilization") {
                        VStack(spacing: 0) {
                            BigNumber(value: String(format: "%.0f", store.cpu.total * 100), unit: "%", size: 40)
                            Text("all cores").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .frame(width: 168, height: 168)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                    VStack(spacing: 8) {
                        LegendRow(color: Theme.cpu[0], label: "User", value: Fmt.percent(store.cpu.user, decimals: 1))
                        LegendRow(color: Theme.cpu[1], label: "System", value: Fmt.percent(store.cpu.system, decimals: 1))
                        LegendRow(color: Theme.track, label: "Idle", value: Fmt.percent(store.cpu.idle, decimals: 1))
                    }
                }
                .frame(width: 290)

                Card {
                    HistoryHeader(title: "History", colors: Theme.cpu) {
                        LegendChip(color: Theme.cpu[0], label: "Total")
                        LegendChip(color: Theme.cpu[1], label: "System")
                    }
                    LiveChart(series: [
                        ChartSeries(id: "Total", series: store.cpuTotal[range], color: Theme.cpu[0]),
                        ChartSeries(id: "System", series: store.cpuSystem[range], color: Theme.cpu[1]),
                    ], xDomain: store.cpuTotal[range].xDomain, yMax: 100, height: 200, label: "CPU history")
                    Divider().overlay(Theme.hairline).padding(.vertical, 14)
                    HStack(alignment: .top) {
                        StatTile(label: "Load 1 min", value: String(format: "%.2f", store.cpu.loadAverage[0]))
                        StatTile(label: "Load 5 min", value: String(format: "%.2f", store.cpu.loadAverage[1]))
                        StatTile(label: "Load 15 min", value: String(format: "%.2f", store.cpu.loadAverage[2]))
                        StatTile(label: "Cores", value: "\(store.info.logicalCores)")
                    }
                }
            }

            Card {
                CardHeader(title: "Cores", subtitle: "Per-core load, grouped by cluster", symbol: "square.grid.3x3.fill", colors: Theme.cpu)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(store.info.clusters) { cluster in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 8) {
                                Text("\(cluster.name.uppercased()) CORES").font(.system(size: 10.5, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(Theme.secondary)
                                Text(clusterAverage(cluster)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Theme.tertiary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                                ForEach(cluster.cores, id: \.self) { core in
                                    CoreTile(index: core,
                                             value: core < store.cpu.cores.count ? store.cpu.cores[core] : 0,
                                             series: core < store.perCore.count ? store.perCore[core] : Series(capacity: 40))
                                }
                            }
                        }
                    }
                }
            }

            TopProcessesCard(metric: .cpu, limit: 8)
        }
    }

    private func clusterAverage(_ cluster: CoreCluster) -> String {
        let values = cluster.cores.compactMap { $0 < store.cpu.cores.count ? store.cpu.cores[$0] : nil }
        guard !values.isEmpty else { return "" }
        return "avg " + Fmt.percent(values.reduce(0, +) / Double(values.count))
    }
}

private struct CoreTile: View {
    let index: Int
    let value: Double
    let series: Series

    var body: some View {
        let color = Theme.heat(value)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Core \(index + 1)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.tertiary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100)).font(Theme.rounded(13)).monospacedDigit().foregroundStyle(Theme.text)
            }
            Sparkline(series: series, color: color, height: 26, label: "Core \(index + 1) history")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.04 + value * 0.12))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.12 + value * 0.3), lineWidth: 0.8))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Core \(index + 1), \(Int(value * 100)) percent")
    }
}
