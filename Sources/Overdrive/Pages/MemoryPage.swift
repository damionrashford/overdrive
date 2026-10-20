import OverdriveCore
import SwiftUI

struct MemoryPage: View {
    @Environment(MonitorStore.self) private var store
    @State private var explaining = false

    private let appColor = Theme.memory[0]
    private let wiredColor = Color.adaptive(light: 0x7C3AED, dark: 0xA78BFA)
    private let compressedColor = Color.adaptive(light: 0x4F46E5, dark: 0x6366F1)
    private let cachedColor = Color.adaptive(light: 0x0284C7, dark: 0x38BDF8).opacity(0.55)

    var body: some View {
        let m = store.memory
        let range = store.settings.chartRange
        PageScaffold(page: .memory, subtitle: "\(Fmt.memory(m.total)) unified memory · shared by CPU and GPU") {
            HStack(spacing: 8) {
                Button("What the numbers mean") { explaining = true }.buttonStyle(GhostButtonStyle(compact: true))
                Pill(text: "Pressure: \(m.pressure.label)", color: pressureColor, symbol: "gauge.with.needle")
            }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "In Use", symbol: "memorychip", colors: Theme.memory)
                    RingGauge(value: m.usedFraction, colors: Theme.memory, lineWidth: 14, label: "Memory used") {
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
                    HistoryHeader(title: "Pressure & Usage", subtitle: "Pressure rises when macOS must compress or swap", colors: Theme.memory) {
                        LegendChip(color: Theme.memory[0], label: "Used")
                        LegendChip(color: pressureColor, label: "Pressure")
                    }
                    LiveChart(series: [
                        ChartSeries(id: "Used", series: store.memoryUsed[range], color: Theme.memory[0]),
                        ChartSeries(id: "Pressure", series: store.memoryPressure[range], color: pressureColor, fill: false),
                    ], xDomain: store.memoryUsed[range].xDomain, yMax: 100, height: 170, label: "Memory history")
                }
                if store.capabilities.canRunShell {
                    FreeMemoryCard().frame(width: 290)
                }
            }

            TopProcessesCard(metric: .memory, limit: 8)
        }
        .sheet(isPresented: $explaining) { MemoryExplainer() }
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

private struct FreeMemoryCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let model = store.maintenance
        let state = model.state("purge")
        Card(highlight: Theme.memory[0].opacity(0.5)) {
            CardHeader(title: "Free Up Memory", symbol: "bolt.fill", colors: Theme.memory)
            Text("Runs macOS’s purge command, which drops the file cache. Useful right before a big job; otherwise macOS manages memory well on its own. Asks for your password.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 14)
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

private struct MemoryExplainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading memory on a Mac").font(Theme.rounded(18, .bold)).foregroundStyle(Theme.text)
            Group {
                Line(term: "Memory pressure", text: "The number that matters. Green means macOS has room; yellow means it is compressing memory; red means it is swapping to disk and apps will stall.")
                Line(term: "App memory", text: "What running apps have asked for. The only part you control, by quitting apps.")
                Line(term: "Wired", text: "Kernel and driver memory that can never be paged out.")
                Line(term: "Compressed", text: "Inactive memory squeezed to make room. Cheap to expand again.")
                Line(term: "Cached files", text: "Recently used files kept in RAM. This is a good thing: it is handed back the instant an app needs it, so “free” memory is not the goal.")
                Line(term: "Swap", text: "Memory moved to the SSD. A few gigabytes is normal after days of uptime; many gigabytes with high pressure means the Mac needs more RAM for what you run.")
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(GlowButtonStyle(colors: Theme.memory)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.background)
    }

    private struct Line: View {
        let term: String
        let text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(term).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
