import OverdriveCore
import SwiftUI

struct ProcessesPage: View {
    @Environment(MonitorStore.self) private var store
    @State private var grouped = true
    @State private var query = ""
    @State private var sort: SortKey = .cpu
    @State private var ascending = false
    @State private var selection: String?

    enum SortKey { case name, cpu, memory, threads, count }

    var body: some View {
        let rows = sortedRows
        let selected = rows.first { $0.id == selection }
        PageScaffold(page: .processes,
                     subtitle: "\(store.processes.count) processes you own · \(Fmt.memory(store.processes.reduce(0) { $0 + $1.memory })) footprint",
                     scrolls: false) {
            HStack(spacing: 10) {
                SearchField(text: $query, prompt: "Filter by name")
                SegmentedTabs(selection: $grouped, options: [(true, "Apps"), (false, "All")], colors: Theme.processes)
            }
        } content: {
            Card(padding: 0) {
                HStack(spacing: 10) {
                    if let selected {
                        (store.icon(for: selected.iconPath)).resizable().frame(width: 20, height: 20)
                        Text(selected.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(selected.count > 1 ? "\(selected.count) processes" : "PID \(selected.pids.first.map(String.init) ?? "")")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    } else {
                        Text("Select a row to quit it").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Button("Quit") { if let selected { store.requestQuit(selected) } }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .disabled(selected == nil)
                    Button("Force Quit") { if let selected { store.requestQuit(selected, force: true) } }
                        .buttonStyle(GlowButtonStyle(colors: [Color(hex: 0xFB7185), Color(hex: 0xE11D48)], compact: true))
                        .disabled(selected == nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().overlay(Theme.hairline)
                header
                Divider().overlay(Theme.hairline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            ProcessTableRow(row: row, grouped: grouped, selected: row.id == selection,
                                            maxCPU: max(100, rows.map(\.cpu).max() ?? 0))
                                .onTapGesture { selection = row.id == selection ? nil : row.id }
                        }
                    }
                    .padding(.vertical, 6)
                    if rows.isEmpty {
                        EmptyHint(symbol: "magnifyingglass", title: "No matches", detail: "Nothing you own matches “\(query)”.")
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Text("Processes owned by other users (root, WindowServer) need administrator rights to inspect and are not listed. They still count toward the CPU and memory totals.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            sortButton("Name", .name).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 46)
            sortButton("CPU", .cpu).frame(width: 150, alignment: .trailing)
            sortButton("Memory", .memory).frame(width: 110, alignment: .trailing)
            sortButton("Threads", .threads).frame(width: 80, alignment: .trailing)
            sortButton(grouped ? "Procs" : "PID", .count).frame(width: 70, alignment: .trailing)
            Spacer().frame(width: 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func sortButton(_ title: String, _ key: SortKey) -> some View {
        Button {
            if sort == key { ascending.toggle() } else { sort = key; ascending = key == .name }
        } label: {
            HStack(spacing: 4) {
                Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6)
                if sort == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .black))
                }
            }
            .foregroundStyle(sort == key ? Theme.processes[0] : Theme.tertiary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sortedRows: [ProcessRow] {
        var rows = store.rows(grouped: grouped)
        if !query.isEmpty { rows = rows.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        rows.sort { a, b in
            let order: Bool
            switch sort {
            case .name: order = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .cpu: order = a.cpu == b.cpu ? a.memory < b.memory : a.cpu < b.cpu
            case .memory: order = a.memory < b.memory
            case .threads: order = a.threads < b.threads
            case .count: order = grouped ? a.count < b.count : (a.pids.first ?? 0) < (b.pids.first ?? 0)
            }
            return ascending ? order : !order
        }
        return rows
    }
}

private struct ProcessTableRow: View {
    @Environment(MonitorStore.self) private var store
    let row: ProcessRow
    let grouped: Bool
    let selected: Bool
    let maxCPU: Double
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                (store.icon(for: row.iconPath)).resizable().interpolation(.high).frame(width: 20, height: 20)
                Text(row.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                GeometryReader { geo in
                    Capsule().fill(Theme.track).overlay(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: Theme.cpu, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(2, geo.size.width * CGFloat(min(1, row.cpu / maxCPU))))
                    }
                }
                .frame(width: 60, height: 4)
                Text(String(format: "%.1f%%", row.cpu)).frame(width: 56, alignment: .trailing)
            }
            .frame(width: 150, alignment: .trailing)
            Text(Fmt.memory(row.memory)).frame(width: 110, alignment: .trailing)
            Text("\(row.threads)").frame(width: 80, alignment: .trailing).foregroundStyle(Theme.secondary)
            Text(grouped ? "\(row.count)" : "\(row.pids.first ?? 0)").frame(width: 70, alignment: .trailing).foregroundStyle(Theme.tertiary)
            HStack {
                IconButton(symbol: "xmark", tint: Theme.tertiary, help: "Quit \(row.name)") { store.requestQuit(row) }
            }
            .frame(width: 52, alignment: .trailing)
            .opacity(hovering || selected ? 1 : 0)
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.processes[1].opacity(0.16) : (hovering ? Color.white.opacity(0.04) : .clear))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
