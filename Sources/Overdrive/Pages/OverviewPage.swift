import OverdriveCore
import SwiftUI

struct OverviewPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        PageScaffold(page: .overview, subtitle: "\(store.info.modelName) · \(store.info.chip) · \(store.info.osVersion)") {
            Pill(text: "Up \(Fmt.duration(store.info.uptime))", color: Theme.secondary, symbol: "clock")
        } content: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                MetricTile(page: .cpu, value: store.cpu.total, headline: Fmt.percent(store.cpu.total),
                           detail: "Load \(String(format: "%.2f", store.cpu.loadAverage[0]))",
                           series: store.cpuTotal)
                MetricTile(page: .memory, value: store.memory.usedFraction, headline: Fmt.percent(store.memory.usedFraction),
                           detail: "\(Fmt.memory(store.memory.used)) of \(Fmt.memory(store.memory.total))",
                           series: store.memoryUsed)
                MetricTile(page: .gpu, value: store.gpu.device, headline: Fmt.percent(store.gpu.device),
                           detail: store.info.gpuCores.map { "\($0)-core GPU" } ?? store.info.gpuName,
                           series: store.gpuDevice)
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
        if page == .disk, let root = store.rootVolume, root.availableFraction < 0.1 {
            return [Color(hex: 0xFCA5A5), Color(hex: 0xEF4444)]
        }
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
                RingGauge(value: value, colors: colors, lineWidth: 10) {
                    VStack(spacing: 0) {
                        Text(headline).font(Theme.rounded(22, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                }
                .frame(width: 112, height: 112)
                .frame(maxWidth: .infinity)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity)
                if let series {
                    Sparkline(series: series, color: colors[0], height: 30)
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
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.smooth(duration: 0.2)) { hovering = h } }
        .scaleEffect(hovering ? 1.012 : 1)
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
                RingGauge(value: Double(report.score) / 100, colors: report.colors, lineWidth: 13) {
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
                            id: "ok", symbol: "checkmark.seal.fill", title: "Everything looks great",
                            detail: "No bottlenecks right now. Overdrive keeps watching from the menu bar.",
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
                Button {
                    if let task = store.maintenance.task("purge") { Task { await store.maintenance.run(task) } }
                } label: { Label(purge == .running ? "Freeing…" : "Free Memory", systemImage: "bolt.fill") }
                    .buttonStyle(GlowButtonStyle(colors: Theme.memory, compact: true))
                    .disabled(purge == .running)
                Button { store.page = .cleanup } label: { Label("Clean Junk", systemImage: "sparkles") }
                    .buttonStyle(GlowButtonStyle(colors: Theme.cleanup, compact: true))
                Button { store.page = .processes } label: { Label("Processes", systemImage: "list.bullet") }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Button { store.page = .maintenance } label: { Label("Maintenance", systemImage: "wrench.and.screwdriver") }
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
                    ChartSeries(id: "down", points: store.netDown.points, color: Theme.download),
                    ChartSeries(id: "up", points: store.netUp.points, color: Theme.upload),
                ], xDomain: store.netDown.xDomain, yMax: top, height: 52, showAxis: false)
            }
        }
        .buttonStyle(.plain)
    }
}

struct RateLabel: View {
    let symbol: String
    let color: Color
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.6).foregroundStyle(Theme.tertiary)
                Text(Fmt.rate(value)).font(Theme.rounded(17)).monospacedDigit().foregroundStyle(Theme.text)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
                        StatTile(label: "Power", value: "AC")
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
