import OverdriveCore
import SwiftUI

struct GPUPage: View {
    @Environment(MonitorStore.self) private var store

    private let rendererColor = Color(hex: 0xF97316)
    private let tilerColor = Color(hex: 0xF43F5E)

    var body: some View {
        let g = store.gpu
        PageScaffold(page: .gpu, subtitle: "\(store.info.gpuName)\(store.info.gpuCores.map { " · \($0) cores" } ?? "") · Metal") {
            if !g.available { Pill(text: "Statistics unavailable", color: Theme.warn, symbol: "exclamationmark.triangle") }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Utilization", symbol: "cube.transparent", colors: Theme.gpu)
                    RingGauge(value: g.device, colors: Theme.gpu, lineWidth: 14) {
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
                    CardHeader(title: "History", subtitle: "Device, fragment (renderer) and geometry (tiler) work",
                               symbol: "waveform.path.ecg", colors: Theme.gpu) {
                        HStack(spacing: 14) {
                            LegendChip(color: Theme.gpu[0], label: "Device")
                            LegendChip(color: rendererColor, label: "Renderer")
                            LegendChip(color: tilerColor, label: "Tiler")
                        }
                    }
                    LiveChart(series: [
                        ChartSeries(id: "device", points: store.gpuDevice.points, color: Theme.gpu[0]),
                        ChartSeries(id: "renderer", points: store.gpuRenderer.points, color: rendererColor, fill: false),
                        ChartSeries(id: "tiler", points: store.gpuTiler.points, color: tilerColor, fill: false),
                    ], xDomain: store.gpuDevice.xDomain, yMax: 100, height: 236)
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
                Card {
                    CardHeader(title: "Reading the numbers", symbol: "info.circle", colors: Theme.gpu)
                    VStack(alignment: .leading, spacing: 10) {
                        Explainer(title: "Device", text: "Share of time the GPU had any work queued. Sustained 90%+ means it is the bottleneck.")
                        Explainer(title: "Renderer", text: "Pixel and compute shading. High in games, video effects and ML inference.")
                        Explainer(title: "Tiler", text: "Geometry processing. High with complex 3D scenes and many windows.")
                    }
                }
            }
        }
    }
}

private struct Explainer: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
