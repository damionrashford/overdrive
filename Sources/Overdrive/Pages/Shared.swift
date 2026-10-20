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
            (store.icon(for: row.iconPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
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
            }
            IconButton(symbol: "xmark", tint: Theme.tertiary, help: "Quit \(row.name)") {
                store.requestQuit(row)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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

struct EmptyHint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.tertiary)
            Text(title).font(Theme.rounded(14)).foregroundStyle(Theme.secondary)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}
