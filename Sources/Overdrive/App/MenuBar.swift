import OverdriveCore
import SwiftUI

struct MenuBarLabel: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        switch store.menuBarStyle {
        case .icon:
            Image(systemName: "gauge.with.dots.needle.67percent")
        case .cpu:
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                Text(Fmt.percent(store.cpu.total)).monospacedDigit()
            }
        case .cpuMemory:
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                Text("\(Fmt.percent(store.cpu.total)) · \(Fmt.percent(store.memory.usedFraction))").monospacedDigit()
            }
        }
    }
}

struct MenuBarPanel: View {
    @Environment(MonitorStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let report = store.health
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LogoMark(size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Overdrive").font(Theme.rounded(14, .bold)).foregroundStyle(Theme.text)
                    Text(store.info.modelName).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                Spacer()
                Pill(text: "\(report.score) · \(report.label)", color: report.colors[1], symbol: "heart.fill")
            }

            HStack(spacing: 0) {
                MiniGauge(title: "CPU", value: store.cpu.total, colors: Theme.cpu)
                MiniGauge(title: "Memory", value: store.memory.usedFraction, colors: Theme.memory)
                MiniGauge(title: "GPU", value: store.gpu.device, colors: Theme.gpu)
                MiniGauge(title: "Disk", value: store.rootVolume?.usedFraction ?? 0,
                          colors: (store.rootVolume?.availableFraction ?? 1) < 0.1 ? [Color(hex: 0xFCA5A5), Theme.bad] : Theme.disk)
            }

            HStack(spacing: 10) {
                RateLabel(symbol: "arrow.down", color: Theme.download, label: "Down", value: store.network.downPerSec)
                RateLabel(symbol: "arrow.up", color: Theme.upload, label: "Up", value: store.network.upPerSec)
            }
            .padding(10)
            .background(CardBackground(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("TOP CPU").font(.system(size: 9.5, weight: .bold)).tracking(0.8).foregroundStyle(Theme.tertiary)
                let rows = store.top(by: \.cpu, limit: 3)
                ForEach(rows) { row in
                    ProcessLine(row: row, metric: .cpu, maxValue: max(100, rows.first?.cpu ?? 0))
                }
            }

            if let issue = report.issues.first {
                HStack(spacing: 8) {
                    Image(systemName: issue.symbol).foregroundStyle(Theme.severity(issue.severity))
                    Text(issue.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button { open(.overview) } label: { Label("Open Overdrive", systemImage: "macwindow") }
                    .buttonStyle(GlowButtonStyle(colors: Theme.cpu, compact: true))
                Button {
                    if let task = store.maintenance.task("purge") { Task { await store.maintenance.run(task) } }
                } label: {
                    Label(store.maintenance.state("purge") == .running ? "Freeing…" : "Free RAM", systemImage: "bolt.fill")
                }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(store.maintenance.state("purge") == .running)
                Spacer()
                IconButton(symbol: "power", help: "Quit Overdrive") { NSApp.terminate(nil) }
            }
            if case .success(let message) = store.maintenance.state("purge") {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.good)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.background.opacity(0.6))
        .preferredColorScheme(.dark)
    }

    private func open(_ page: Page) {
        store.page = page
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MiniGauge: View {
    let title: String
    let value: Double
    let colors: [Color]

    var body: some View {
        VStack(spacing: 6) {
            RingGauge(value: value, colors: colors, lineWidth: 6) {
                Text(String(format: "%.0f", value * 100)).font(Theme.rounded(13, .bold)).monospacedDigit().foregroundStyle(Theme.text)
            }
            .frame(width: 56, height: 56)
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
