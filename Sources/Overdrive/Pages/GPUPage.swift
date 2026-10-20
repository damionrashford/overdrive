import OverdriveCore
import SwiftUI

struct GPUPage: View {
    @Environment(MonitorStore.self) private var store

    private let rendererColor = Color.adaptive(light: 0xC2410C, dark: 0xF97316)
    private let tilerColor = Color.adaptive(light: 0xBE123C, dark: 0xF43F5E)

    var body: some View {
        let g = store.gpu
        let range = store.settings.chartRange
        PageScaffold(page: .gpu, subtitle: "\(store.info.gpuName)\(store.info.gpuCores.map { " · \($0) cores" } ?? "") · Metal") {
            HStack(spacing: 8) {
                if let t = store.sensors.average(.gpu) {
                    Pill(text: store.settings.temperature(t), color: Theme.thermal(t), symbol: "thermometer.medium")
                }
                if !g.available { Pill(text: "Statistics unavailable", color: Theme.warn, symbol: "exclamationmark.triangle") }
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Utilization", symbol: "cube.transparent", colors: Theme.gpu)
                    RingGauge(value: g.device, colors: Theme.gpu, lineWidth: 14, label: "GPU utilization") {
                        VStack(spacing: 0) {
                            BigNumber(value: String(format: "%.0f", g.device * 100), unit: "%", size: 40)
                            Text("device busy").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .frame(width: 168, height: 168)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                    VStack(spacing: 8) {
                        LegendRow(color: Theme.gpu[0], label: "Device", value: Fmt.percent(g.device))
                        LegendRow(color: rendererColor, label: "Renderer", value: Fmt.percent(g.renderer))
                        LegendRow(color: tilerColor, label: "Tiler", value: Fmt.percent(g.tiler))
                    }
                }
                .frame(width: 290)

                Card {
                    HistoryHeader(title: "History", subtitle: "Device, fragment (renderer) and geometry (tiler) work", colors: Theme.gpu) {
                        LegendChip(color: Theme.gpu[0], label: "Device")
                        LegendChip(color: rendererColor, label: "Renderer")
                        LegendChip(color: tilerColor, label: "Tiler")
                    }
                    LiveChart(series: [
                        ChartSeries(id: "Device", series: store.gpuDevice[range], color: Theme.gpu[0]),
                        ChartSeries(id: "Renderer", series: store.gpuRenderer[range], color: rendererColor, fill: false),
                        ChartSeries(id: "Tiler", series: store.gpuTiler[range], color: tilerColor, fill: false),
                    ], xDomain: store.gpuDevice[range].xDomain, yMax: 100, height: 236, label: "GPU history")
                }
            }

            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "GPU Memory", subtitle: "Unified memory the GPU driver holds", symbol: "square.stack.3d.down.right",
                               colors: Theme.gpu)
                    let limit = max(store.info.gpuWorkingSet, g.allocatedMemory, 1)
                    SegmentBar(segments: [
                        Segment(id: "inuse", value: Double(g.inUseMemory), color: Theme.gpu[1]),
                        Segment(id: "alloc", value: Double(g.allocatedMemory > g.inUseMemory ? g.allocatedMemory - g.inUseMemory : 0),
                                color: Theme.gpu[0].opacity(0.4)),
                    ], total: Double(limit), height: 16)
                    .padding(.bottom, 16)
                    HStack(alignment: .top) {
                        StatTile(label: "In use", value: Fmt.memory(g.inUseMemory))
                        StatTile(label: "Allocated", value: Fmt.memory(g.allocatedMemory))
                        StatTile(label: "Working set limit", value: Fmt.memory(store.info.gpuWorkingSet), caption: "Metal recommended max")
                    }
                }
                if store.sensors.available, let gpuTemp = store.sensors.average(.gpu) {
                    Card {
                        CardHeader(title: "Temperature", subtitle: "Average of the GPU cluster sensors", symbol: "thermometer.medium", colors: Theme.sensors) {
                            Button("All sensors") { store.page = .sensors }.buttonStyle(GhostButtonStyle(compact: true))
                        }
                        HStack(alignment: .top) {
                            StatTile(label: "GPU", value: store.settings.temperature(gpuTemp), tint: Theme.thermal(gpuTemp))
                            StatTile(label: "Hottest sensor", value: store.sensors.hottest(.gpu).map { store.settings.temperature($0) } ?? "–")
                            if let power = store.sensors.power.first(where: { $0.key == "PGTR" || $0.key == "PG0R" }) {
                                StatTile(label: "GPU power", value: Fmt.watts(power.watts))
                            }
                        }
                    }
                    .frame(width: 360)
                }
            }
        }
    }
}
