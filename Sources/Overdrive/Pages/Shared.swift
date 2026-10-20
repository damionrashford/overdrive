import OverdriveCore
import SwiftUI

/// A compact process row used in the "top consumers" lists.
struct ProcessLine: View {
    @Environment(MonitorStore.self) private var store
    let row: ProcessRow
    let metric: Metric
    var maxValue: Double

    enum Metric { case cpu, memory }

    @State private var hovering = false

    var body: some View {
        let value = metric == .cpu ? row.cpu : Double(row.memory)
        let colors = metric == .cpu ? Theme.cpu : Theme.memory
        HStack(spacing: 11) {
            store.icon(for: row.iconPath)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if row.count > 1 {
                        Text("\(row.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer(minLength: 6)
                    Text(metric == .cpu ? String(format: "%.1f%%", row.cpu) : Fmt.memory(row.memory))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondary)
                }
                GeometryReader { geo in
                    Capsule().fill(Theme.track)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, geo.size.width * CGFloat(maxValue > 0 ? min(1, value / maxValue) : 0)))
                        }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            if store.capabilities.canQuitProcesses {
                IconButton(symbol: "xmark", tint: Theme.tertiary, help: "Quit \(row.name)") {
                    store.requestQuit(row)
                }
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.name), \(metric == .cpu ? String(format: "%.0f percent CPU", row.cpu) : Fmt.memory(row.memory))")
    }
}

struct TopProcessesCard: View {
    @Environment(MonitorStore.self) private var store
    let metric: ProcessLine.Metric
    var limit = 6

    var body: some View {
        let rows = metric == .cpu ? store.top(by: \.cpu, limit: limit) : store.topByMemory(limit: limit)
        let maxValue = metric == .cpu ? max(100, rows.first?.cpu ?? 0) : Double(rows.first?.memory ?? 1)
        Card {
            CardHeader(title: metric == .cpu ? "Top CPU" : "Top Memory",
                       subtitle: "Apps and processes, helpers grouped",
                       symbol: metric == .cpu ? "flame" : "memorychip",
                       colors: metric == .cpu ? Theme.cpu : Theme.memory) {
                Button("All") { store.page = .processes }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
            if rows.isEmpty {
                Text("Sampling…").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    ProcessLine(row: row, metric: metric, maxValue: maxValue)
                }
            }
        }
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
        .accessibilityElement(children: .combine)
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

/// Header + range picker for every history card.
struct HistoryHeader<Legend: View>: View {
    @Environment(MonitorStore.self) private var store
    let title: String
    var subtitle: String?
    let colors: [Color]
    @ViewBuilder var legend: () -> Legend

    var body: some View {
        @Bindable var settings = store.settings
        CardHeader(title: title, subtitle: subtitle, symbol: "waveform.path.ecg", colors: colors) {
            HStack(spacing: 14) {
                legend()
                RangePicker(range: $settings.chartRange, colors: colors)
            }
        }
    }
}

extension HistoryHeader where Legend == EmptyView {
    init(title: String, subtitle: String? = nil, colors: [Color]) {
        self.init(title: title, subtitle: subtitle, colors: colors) { EmptyView() }
    }
}

/// Opens Finder on a path and shows it in a tooltip-friendly form.
func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
