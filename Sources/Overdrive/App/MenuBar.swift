import AppKit
import OverdriveCore
import SwiftUI

struct MenuBarLabel: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        switch store.settings.menuBarStyle {
        case .icon:
            Image(systemName: "gauge.with.dots.needle.67percent")
        case .text:
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(store.settings.menuBarModules.map(textValue).joined(separator: " · ")).monospacedDigit()
            }
        case .graph:
            Image(nsImage: MenuBarGraphs.render(store: store))
        }
    }

    private func textValue(_ module: MenuBarModule) -> String {
        switch module {
        case .cpu: Fmt.percent(store.cpu.total)
        case .memory: Fmt.percent(store.memory.usedFraction)
        case .network: Fmt.rate(store.network.downPerSec)
        case .temperature: store.sensors.average(.cpu).map { store.settings.temperature($0) } ?? "–"
        }
    }
}

/// Draws compact 18-point history graphs for the menu bar. Rendered once per sample, which is far
/// cheaper than a live SwiftUI view inside the status item.
@MainActor
enum MenuBarGraphs {
    static func render(store: MonitorStore) -> NSImage {
        let modules = store.settings.menuBarModules.isEmpty ? [.cpu] : store.settings.menuBarModules
        let width: CGFloat = 34, height: CGFloat = 16, gap: CGFloat = 6
        let total = CGFloat(modules.count) * width + CGFloat(modules.count - 1) * gap
        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var x: CGFloat = 0
            for module in modules {
                let (points, top) = series(for: module, store: store)
                let frame = CGRect(x: x, y: 0, width: width, height: height)
                ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.12).cgColor)
                ctx.fill(frame.insetBy(dx: 0, dy: 0))
                if points.count > 1 {
                    let path = CGMutablePath()
                    let span = Double(max(1, points.count - 1))
                    for (i, p) in points.enumerated() {
                        let px = frame.minX + frame.width * CGFloat(Double(i) / span)
                        let py = frame.minY + frame.height * CGFloat(min(1, max(0, p.value / max(top, 0.0001))))
                        i == 0 ? path.move(to: CGPoint(x: px, y: py)) : path.addLine(to: CGPoint(x: px, y: py))
                    }
                    let fill = path.mutableCopy()!
                    fill.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
                    fill.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
                    fill.closeSubpath()
                    ctx.addPath(fill)
                    ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.35).cgColor)
                    ctx.fillPath()
                    ctx.addPath(path)
                    ctx.setStrokeColor(NSColor.labelColor.cgColor)
                    ctx.setLineWidth(1.2)
                    ctx.strokePath()
                }
                x += width + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func series(for module: MenuBarModule, store: MonitorStore) -> ([ChartPoint], Double) {
        switch module {
        case .cpu: return (Array(store.cpuTotal.live.points.suffix(40)), 100)
        case .memory: return (Array(store.memoryUsed.live.points.suffix(40)), 100)
        case .network:
            let points = Array(store.netDown.live.points.suffix(40))
            return (points, niceCeiling(points.map(\.value).max() ?? 0, minimum: 100_000))
        case .temperature: return (Array(store.cpuTemperature.live.points.suffix(40)), 120)
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
                          colors: (store.rootVolume?.availableFraction ?? 1) < 0.1 ? Theme.danger : Theme.disk)
            }

            HStack(spacing: 10) {
                RateLabel(symbol: "arrow.down", color: Theme.download, label: "Down", value: store.network.downPerSec)
                RateLabel(symbol: "arrow.up", color: Theme.upload, label: "Up", value: store.network.upPerSec)
                if let t = store.sensors.average(.cpu) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CPU TEMP").font(.system(size: 9.5, weight: .bold)).tracking(0.6).foregroundStyle(Theme.tertiary)
                        Text(store.settings.temperature(t)).font(Theme.rounded(17)).monospacedDigit().foregroundStyle(Theme.thermal(t))
                    }
                }
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
                if store.capabilities.canRunShell, let purge = store.maintenance.task("purge") {
                    Button {
                        Task { await store.maintenance.run(purge) }
                    } label: {
                        Label(store.maintenance.state("purge") == .running ? "Freeing…" : "Free Memory", systemImage: "bolt.fill")
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    .disabled(store.maintenance.state("purge") == .running)
                }
                Spacer()
                IconButton(symbol: "power", help: "Quit Overdrive") { NSApp.terminate(nil) }
            }
            if case .success(let message) = store.maintenance.state("purge") {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.good)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.background)
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
            RingGauge(value: value, colors: colors, lineWidth: 6, label: title) {
                Text(String(format: "%.0f", value * 100)).font(Theme.rounded(13, .bold)).monospacedDigit().foregroundStyle(Theme.text)
            }
            .frame(width: 56, height: 56)
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
