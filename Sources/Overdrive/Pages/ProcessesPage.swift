import OverdriveCore
import SwiftUI

struct ProcessesPage: View {
    @Environment(MonitorStore.self) private var store
    @State private var grouped = true
    @State private var query = ""
    @State private var sort: SortKey = .cpu
    @State private var ascending = false
    @State private var selection: String?

    enum SortKey { case name, cpu, memory, disk, threads, count }

    var body: some View {
        let rows = sortedRows
        let selected = rows.first { $0.id == selection }
        let disk = store.capabilities.hasProcessDiskIO
        PageScaffold(page: .processes,
                     subtitle: "\(store.processes.count) processes you own · \(Fmt.memory(store.processes.reduce(0) { $0 + $1.memory })) \(store.capabilities.isSandboxed ? "resident" : "footprint")",
                     scrolls: false) {
            HStack(spacing: 10) {
                SearchField(text: $query, prompt: "Filter by name")
                SegmentedTabs(selection: $grouped, options: [(true, "Apps"), (false, "All")], colors: Theme.processes)
            }
        } content: {
            Card(padding: 0) {
                DetailBar(row: selected)
                Divider().overlay(Theme.hairline)
                header(disk: disk)
                Divider().overlay(Theme.hairline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            ProcessTableRow(row: row, grouped: grouped, selected: row.id == selection, disk: disk,
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
            Text(store.capabilities.isSandboxed
                 ? "Processes owned by other users are not listed, and the App Store edition cannot quit other apps; use the app’s own Quit command. The direct edition adds Quit and a disk I/O column."
                 : "Processes owned by other users (root, WindowServer) need administrator rights to inspect and are not listed. They still count toward the CPU and memory totals.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
    }

    private func header(disk: Bool) -> some View {
        HStack(spacing: 0) {
            sortButton("Name", .name).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 46)
            sortButton("CPU", .cpu).frame(width: 150, alignment: .trailing)
            sortButton("Memory", .memory).frame(width: 100, alignment: .trailing)
            if disk {
                sortButton("Disk I/O", .disk).frame(width: 110, alignment: .trailing)
            }
            sortButton("Threads", .threads).frame(width: 76, alignment: .trailing)
            sortButton(grouped ? "Procs" : "PID", .count).frame(width: 66, alignment: .trailing)
            Spacer().frame(width: store.capabilities.canQuitProcesses ? 52 : 16)
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
        .accessibilityLabel("Sort by \(title)")
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
            case .disk: order = a.diskRead + a.diskWrite < b.diskRead + b.diskWrite
            case .threads: order = a.threads < b.threads
            case .count: order = grouped ? a.count < b.count : (a.pids.first ?? 0) < (b.pids.first ?? 0)
            }
            return ascending ? order : !order
        }
        return rows
    }
}

/// What is selected, with the facts a person wants before quitting something.
private struct DetailBar: View {
    @Environment(MonitorStore.self) private var store
    let row: ProcessRow?

    var body: some View {
        HStack(spacing: 10) {
            if let row {
                store.icon(for: row.iconPath).resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(row.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if let sample = sample(for: row) {
                            Text("PID \(sample.pid)\(sample.parent > 0 ? " · parent \(parentName(sample.parent))" : "") · started \(sample.startTime.formatted(.relative(presentation: .named))) · CPU time \(Fmt.duration(sample.cpuTimeSeconds))")
                                .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                        } else if row.count > 1 {
                            Text("\(row.count) processes").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    if let path = path(for: row) {
                        Text(abbreviated(path)).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if let path = path(for: row) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.bundlePath ?? path)]) }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
                if store.capabilities.canQuitProcesses {
                    Button("Quit") { store.requestQuit(row) }.buttonStyle(GhostButtonStyle(compact: true))
                    Button("Force Quit") { store.requestQuit(row, force: true) }
                        .buttonStyle(GlowButtonStyle(colors: Theme.danger, compact: true))
                }
            } else {
                Text("Select a row for details").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 54)
    }

    private func sample(for row: ProcessRow) -> ProcessSample? {
        guard row.count == 1, let pid = row.pids.first else { return nil }
        return store.processes.first { $0.pid == pid }
    }

    private func path(for row: ProcessRow) -> String? {
        if let bundle = row.bundlePath { return bundle }
        return sample(for: row)?.path.nonEmpty ?? row.iconPath.nonEmpty
    }

    private func parentName(_ pid: pid_t) -> String {
        store.processes.first { $0.pid == pid }?.name ?? (pid == 1 ? "launchd" : "\(pid)")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct ProcessTableRow: View {
    @Environment(MonitorStore.self) private var store
    let row: ProcessRow
    let grouped: Bool
    let selected: Bool
    let disk: Bool
    let maxCPU: Double

    var body: some View {
        HoverRow(selected: selected, accent: Theme.processes[1]) { hovering in
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    store.icon(for: row.iconPath).resizable().interpolation(.high).frame(width: 20, height: 20)
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
                Text(Fmt.memory(row.memory)).frame(width: 100, alignment: .trailing)
                if disk {
                    Text(row.diskRead + row.diskWrite > 1000 ? Fmt.rate(row.diskRead + row.diskWrite) : "–").frame(width: 110, alignment: .trailing).foregroundStyle(Theme.secondary)
                }
                Text("\(row.threads)").frame(width: 76, alignment: .trailing).foregroundStyle(Theme.secondary)
                Text(grouped ? "\(row.count)" : "\(row.pids.first ?? 0)").frame(width: 66, alignment: .trailing).foregroundStyle(Theme.tertiary)
                if store.capabilities.canQuitProcesses {
                    HStack {
                        IconButton(symbol: "xmark", tint: Theme.tertiary, help: "Quit \(row.name)") { store.requestQuit(row) }
                    }
                    .frame(width: 52, alignment: .trailing)
                    .opacity(hovering || selected ? 1 : 0)
                } else {
                    Spacer().frame(width: 16)
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name), \(String(format: "%.0f", row.cpu)) percent CPU, \(Fmt.memory(row.memory))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
