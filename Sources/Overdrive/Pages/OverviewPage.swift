import OverdriveCore
import SwiftUI

struct OverviewPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        PageScaffold(page: .overview, subtitle: "\(store.info.modelName) · \(store.info.chip) · \(store.info.osVersion)") {
            Pill(text: "Up \(Fmt.duration(store.info.uptime))", color: Theme.secondary, symbol: "clock")
        } content: {
            if let update = store.updates.available {
                Notice(symbol: "arrow.down.circle.fill", color: Theme.cpu[0],
                       text: "Overdrive \(update.version) is available. You have \(Bundle.main.shortVersion).") {
                    Link("Download", destination: update.url).font(.system(size: 12, weight: .semibold))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                MetricTile(page: .cpu, value: store.cpu.total, headline: Fmt.percent(store.cpu.total),
                           detail: store.sensors.average(.cpu).map { "\(store.settings.temperature($0)) · load \(String(format: "%.1f", store.cpu.loadAverage[0]))" }
                                   ?? "Load \(String(format: "%.2f", store.cpu.loadAverage[0]))",
                           series: store.cpuTotal.live)
                MetricTile(page: .memory, value: store.memory.usedFraction, headline: Fmt.percent(store.memory.usedFraction),
                           detail: "\(Fmt.memory(store.memory.used)) of \(Fmt.memory(store.memory.total))",
                           series: store.memoryUsed.live)
                MetricTile(page: .gpu, value: store.gpu.device, headline: Fmt.percent(store.gpu.device),
                           detail: store.info.gpuCores.map { "\($0)-core GPU" } ?? store.info.gpuName,
                           series: store.gpuDevice.live)
                MetricTile(page: .disk, value: store.rootVolume?.usedFraction ?? 0,
                           headline: Fmt.percent(store.rootVolume?.usedFraction ?? 0),
                           detail: "\(Fmt.storage(store.rootVolume?.available ?? 0)) available",
                           series: nil)
            }
            HStack(alignment: .top, spacing: 16) {
                HealthCard()
                    .frame(maxHeight: .infinity)
                VStack(spacing: 16) {
                    NetworkSummaryCard()
                    SystemSummaryCard()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !store.ai.runtimes.isEmpty {
                AISummaryCard()
            }
            HStack(alignment: .top, spacing: 16) {
                TopProcessesCard(metric: .cpu, limit: 5)
                TopProcessesCard(metric: .memory, limit: 5)
            }
        }
    }
}

private struct MetricTile: View {
    @Environment(MonitorStore.self) private var store
    let page: Page
    let value: Double
    let headline: String
    let detail: String
    let series: Series?
    @State private var hovering = false

    private var colors: [Color] {
        if page == .disk, let root = store.rootVolume, root.availableFraction < 0.1 { return Theme.danger }
        return page.accent
    }

    var body: some View {
        Button { store.page = page } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconBadge(symbol: page.symbol, colors: colors, size: 24)
                    Text(page.title).font(Theme.rounded(13.5)).foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiary).opacity(hovering ? 1 : 0)
                }
                RingGauge(value: value, colors: colors, lineWidth: 10, label: page.title) {
                    Text(headline).font(Theme.rounded(22, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                }
                .frame(width: 112, height: 112)
                .frame(maxWidth: .infinity)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity)
                if let series {
                    Sparkline(series: series, color: colors[0], height: 30, label: "\(page.title) history")
                } else {
                    SegmentBar(segments: [
                        Segment(id: "used", value: Double(store.rootVolume?.used ?? 0), color: colors[1]),
                        Segment(id: "purge", value: Double(store.rootVolume?.purgeable ?? 0), color: colors[0].opacity(0.45)),
                    ], total: Double(store.rootVolume?.total ?? 1), height: 8)
                    .padding(.vertical, 11)
                }
            }
            .padding(16)
            .background(CardBackground(highlight: hovering ? colors[0] : nil))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.smooth(duration: 0.2)) { hovering = h } }
        .scaleEffect(hovering ? 1.012 : 1)
        .accessibilityLabel("\(page.title) \(headline), \(detail). Opens the \(page.title) page.")
    }
}

private struct HealthCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let report = store.health
        Card(highlight: report.colors[1].opacity(0.6)) {
            CardHeader(title: "System Health", subtitle: "Live score from CPU, memory, storage and heat",
                       symbol: "heart.text.square", colors: report.colors)
            HStack(alignment: .center, spacing: 22) {
                RingGauge(value: Double(report.score) / 100, colors: report.colors, lineWidth: 13, label: "Health score") {
                    VStack(spacing: -2) {
                        Text("\(report.score)").font(Theme.rounded(38, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                        Text(report.label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1)
                            .foregroundStyle(report.colors[1])
                    }
                }
                .frame(width: 138, height: 138)
                VStack(alignment: .leading, spacing: 10) {
                    if report.issues.isEmpty {
                        RecommendationView(rec: Recommendation(
                            id: "ok", symbol: "checkmark.seal.fill", title: "No bottlenecks right now",
                            detail: "CPU, memory pressure, storage and temperature are all within normal range.",
                            severity: 0, action: nil, actionLabel: nil))
                        RecommendationView(rec: Recommendation(
                            id: "clean", symbol: "sparkles", title: "Reclaim space anyway",
                            detail: "Scan caches, logs and developer junk.", severity: 0,
                            action: .page(.cleanup), actionLabel: "Scan"))
                    }
                    ForEach(report.issues.prefix(3)) { rec in
                        RecommendationView(rec: rec)
                    }
                }
            }
            Spacer(minLength: 18)
            QuickActions()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickActions: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let purge = store.maintenance.state("purge")
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.hairline)
            HStack(spacing: 8) {
                Text("QUICK ACTIONS").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.tertiary)
                Spacer()
                if case .success(let message) = purge {
                    Text(message).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.good)
                }
            }
            HStack(spacing: 8) {
                if store.capabilities.canRunShell, let task = store.maintenance.task("purge") {
                    Button {
                        Task { await store.maintenance.run(task) }
                    } label: { Label(purge == .running ? "Freeing…" : "Free Memory", systemImage: "bolt.fill") }
                        .buttonStyle(GlowButtonStyle(colors: Theme.memory, compact: true))
                        .disabled(purge == .running)
                }
                Button { store.page = .cleanup } label: { Label("Clean Junk", systemImage: "sparkles") }
                    .buttonStyle(GlowButtonStyle(colors: Theme.cleanup, compact: true))
                Button { store.page = .processes } label: { Label("Processes", systemImage: "list.bullet") }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Button { store.page = .apps } label: { Label("Uninstall", systemImage: "trash") }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
    }
}

private struct RecommendationView: View {
    @Environment(MonitorStore.self) private var store
    let rec: Recommendation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: rec.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.severity(rec.severity))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.severity(rec.severity).opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(rec.detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let action = rec.action, let label = rec.actionLabel {
                Button(label) {
                    switch action {
                    case .page(let page): store.page = page
                    case .quit(let row): store.requestQuit(row)
                    }
                }
                .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NetworkSummaryCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Button { store.page = .network } label: {
            Card {
                HStack(spacing: 18) {
                    RateLabel(symbol: "arrow.down", color: Theme.download, label: "Download", value: store.network.downPerSec)
                    RateLabel(symbol: "arrow.up", color: Theme.upload, label: "Upload", value: store.network.upPerSec)
                }
                .padding(.bottom, 10)
                let top = niceCeiling(max(store.netDown.maxValue, store.netUp.maxValue), minimum: 50_000)
                LiveChart(series: [
                    ChartSeries(id: "down", series: store.netDown.live, color: Theme.download),
                    ChartSeries(id: "up", series: store.netUp.live, color: Theme.upload),
                ], xDomain: store.netDown.live.xDomain, yMax: top, height: 52, showAxis: false, label: "Network history",
                          format: { Fmt.rate($0) })
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SystemSummaryCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    StatTile(label: "Thermal", value: store.thermalLabel, tint: store.thermalColor)
                    StatTile(label: "Pressure", value: store.memory.pressure.label,
                             tint: Theme.severity(store.memory.pressure == .normal ? 0 : (store.memory.pressure == .warning ? 1 : 2)))
                    StatTile(label: "Swap", value: Fmt.memory(store.memory.swapUsed))
                }
                GridRow {
                    if store.power.hasBattery {
                        StatTile(label: "Battery", value: Fmt.percent(store.power.percent),
                                 caption: store.power.isCharging ? "Charging" : (store.power.onAC ? "On power" : batteryCaption),
                                 tint: store.power.percent < 0.2 && !store.power.onAC ? Theme.bad : Theme.text)
                        StatTile(label: "Battery Health", value: store.power.health.map { Fmt.percent($0) } ?? "–",
                                 caption: store.power.cycleCount.map { "\($0) cycles" })
                    } else {
                        StatTile(label: "Power", value: store.sensors.systemPower.map { Fmt.watts($0) } ?? "AC")
                        StatTile(label: "Uptime", value: Fmt.duration(store.info.uptime))
                    }
                    StatTile(label: "Processes", value: "\(store.processes.count)", caption: "yours")
                }
            }
        }
    }

    private var batteryCaption: String {
        if let m = store.power.minutesToEmpty { return "\(m / 60)h \(m % 60)m left" }
        return "On battery"
    }
}

private struct AISummaryCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Button { store.page = .ai } label: {
            Card {
                HStack(spacing: 16) {
                    IconBadge(symbol: "brain", colors: Theme.ai, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.ai.runtimes.map(\.name).joined(separator: ", ") + (store.ai.runtimes.count == 1 ? " is running" : " are running"))
                            .font(Theme.rounded(14)).foregroundStyle(Theme.text)
                        Text(store.ai.loaded.isEmpty
                             ? "No model loaded in memory."
                             : "\(store.ai.loaded.count) model\(store.ai.loaded.count == 1 ? "" : "s") in memory · \(Fmt.memory(store.ai.loadedBytes))")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if let headroom = store.ai.headroom {
                        StatTile(label: "Room for a model", value: Fmt.memory(headroom.availableNow), caption: "of unified memory now")
                            .frame(width: 180)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
