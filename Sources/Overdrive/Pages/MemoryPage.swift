import OverdriveCore
import SwiftUI

struct MemoryPage: View {
    @Environment(MonitorStore.self) private var store

    private let appColor = Color(hex: 0xE879F9)
    private let wiredColor = Color(hex: 0xA78BFA)
    private let compressedColor = Color(hex: 0x6366F1)
    private let cachedColor = Color(hex: 0x38BDF8).opacity(0.55)

    var body: some View {
        let m = store.memory
        PageScaffold(page: .memory, subtitle: "\(Fmt.memory(m.total)) unified memory · shared by CPU and GPU") {
            Pill(text: "Pressure: \(m.pressure.label)", color: pressureColor, symbol: "gauge.with.needle")
        } content: {
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "In Use", symbol: "memorychip", colors: Theme.memory)
                    RingGauge(value: m.usedFraction, colors: Theme.memory, lineWidth: 14) {
                        VStack(spacing: 0) {
                            BigNumber(value: String(format: "%.1f", Double(m.used) / 1_073_741_824), unit: "GB", size: 36)
                            Text("of \(Fmt.memory(m.total))").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .frame(width: 168, height: 168)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)
                    HStack(alignment: .top) {
                        StatTile(label: "Swap", value: Fmt.memory(m.swapUsed), caption: "of \(Fmt.memory(m.swapTotal))")
                        StatTile(label: "Available", value: Fmt.memory(m.free + m.cached), caption: "free + cache")
                    }
                }
                .frame(width: 290)

                Card {
                    CardHeader(title: "Breakdown", subtitle: "How macOS is using RAM right now", symbol: "chart.bar.xaxis", colors: Theme.memory)
                    SegmentBar(segments: [
                        Segment(id: "app", value: Double(m.app), color: appColor),
                        Segment(id: "wired", value: Double(m.wired), color: wiredColor),
                        Segment(id: "compressed", value: Double(m.compressed), color: compressedColor),
                        Segment(id: "cached", value: Double(m.cached), color: cachedColor),
                    ], total: Double(max(1, m.total)), height: 18)
                    .padding(.bottom, 16)
                    Grid(horizontalSpacing: 28, verticalSpacing: 10) {
                        GridRow {
                            LegendRow(color: appColor, label: "App memory", value: Fmt.memory(m.app))
                            LegendRow(color: cachedColor, label: "Cached files", value: Fmt.memory(m.cached))
                        }
                        GridRow {
                            LegendRow(color: wiredColor, label: "Wired", value: Fmt.memory(m.wired))
                            LegendRow(color: Theme.track, label: "Free", value: Fmt.memory(m.free))
                        }
                        GridRow {
                            LegendRow(color: compressedColor, label: "Compressed", value: Fmt.memory(m.compressed))
                            LegendRow(color: .clear, label: "Total", value: Fmt.memory(m.total))
                        }
                    }
                    Divider().overlay(Theme.hairline).padding(.vertical, 14)
                    HStack(alignment: .top) {
                        StatTile(label: "Page-ins", value: rate(m.pageInsPerSec), caption: "pages/s")
                        StatTile(label: "Page-outs", value: rate(m.pageOutsPerSec), caption: "pages/s")
                        StatTile(label: "Swap-ins", value: rate(m.swapInsPerSec), caption: "pages/s")
                        StatTile(label: "Swap-outs", value: rate(m.swapOutsPerSec), caption: "pages/s")
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Pressure & Usage", subtitle: "Pressure rises when macOS must compress or swap",
                               symbol: "waveform.path.ecg", colors: Theme.memory) {
                        HStack(spacing: 14) {
                            LegendChip(color: Theme.memory[0], label: "Used")
                            LegendChip(color: pressureColor, label: "Pressure")
                        }
                    }
                    LiveChart(series: [
                        ChartSeries(id: "used", points: store.memoryUsed.points, color: Theme.memory[0]),
                        ChartSeries(id: "pressure", points: store.memoryPressure.points, color: pressureColor, fill: false),
                    ], xDomain: store.memoryUsed.xDomain, yMax: 100, height: 170)
                }
                FreeMemoryCard()
                    .frame(width: 290)
            }

            TopProcessesCard(metric: .memory, limit: 8)
        }
    }

    private var pressureColor: Color {
        switch store.memory.pressure {
        case .normal: Theme.good
        case .warning: Theme.warn
        case .critical: Theme.bad
        }
    }

    private func rate(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(format: "%.0f", v)
    }
}

struct FreeMemoryCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let model = store.maintenance
        let state = model.state("purge")
        Card(highlight: Theme.memory[0].opacity(0.5)) {
            CardHeader(title: "Free Up Memory", symbol: "bolt.fill", colors: Theme.memory)
            Text("Releases inactive file cache so new apps get free RAM instantly. macOS asks for your password.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
            TaskStatusLine(state: state)
                .padding(.bottom, 12)
            Button {
                if let task = model.task("purge") { Task { await model.run(task) } }
            } label: {
                HStack(spacing: 6) {
                    if state == .running { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "bolt.fill") }
                    Text(state == .running ? "Freeing…" : "Free Memory")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle(colors: Theme.memory))
            .disabled(state == .running)
        }
    }
}

struct TaskStatusLine: View {
    let state: MaintenanceModel.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            Label("Working…", systemImage: "hourglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.good)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.bad).lineLimit(3)
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.tertiary)
        }
    }
}
