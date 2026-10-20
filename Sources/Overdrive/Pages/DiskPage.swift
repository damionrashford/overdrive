import OverdriveCore
import SwiftUI

struct DiskPage: View {
    @Environment(MonitorStore.self) private var store

    private let readColor = Theme.disk[0]
    private let writeColor = Color.adaptive(light: 0x0284C7, dark: 0x38BDF8)

    var body: some View {
        @Bindable var store = store
        let range = store.settings.chartRange
        PageScaffold(page: .disk, subtitle: subtitle) {
            HStack(spacing: 10) {
                SegmentedTabs(selection: $store.storageTab, options: [(.volumes, "Volumes"), (.explorer, "Space Map")], colors: Theme.disk)
                if store.storageTab == .volumes {
                    Button { store.refreshVolumes() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
            }
        } content: {
            switch store.storageTab {
            case .volumes:
                ForEach(store.volumes) { volume in
                    VolumeCard(volume: volume)
                }
                if store.volumes.isEmpty {
                    Card { EmptyHint(symbol: "internaldrive", title: "Reading volumes…", detail: "") }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        HistoryHeader(title: "Disk Activity", subtitle: "All physical disks", colors: Theme.disk) {
                            LegendChip(color: readColor, label: "Read")
                            LegendChip(color: writeColor, label: "Write")
                        }
                        HStack(spacing: 18) {
                            RateLabel(symbol: "arrow.down.doc", color: readColor, label: "Read", value: store.diskIO.readPerSec)
                            RateLabel(symbol: "arrow.up.doc", color: writeColor, label: "Write", value: store.diskIO.writePerSec)
                        }
                        .padding(.bottom, 12)
                        let top = niceCeiling(max(store.diskRead[range].maxValue, store.diskWrite[range].maxValue), minimum: 1_000_000)
                        LiveChart(series: [
                            ChartSeries(id: "Read", series: store.diskRead[range], color: readColor),
                            ChartSeries(id: "Write", series: store.diskWrite[range], color: writeColor),
                        ], xDomain: store.diskRead[range].xDomain, yMax: top, height: 160, label: "Disk activity", format: { Fmt.rate($0) })
                    }
                    Card {
                        CardHeader(title: "Since Boot", symbol: "clock.arrow.circlepath", colors: Theme.disk)
                        VStack(alignment: .leading, spacing: 16) {
                            StatTile(label: "Data read", value: Fmt.storage(store.diskIO.totalRead))
                            StatTile(label: "Data written", value: Fmt.storage(store.diskIO.totalWritten))
                            StatTile(label: "Operations", value: String(format: "%.0f / s", store.diskIO.readOpsPerSec + store.diskIO.writeOpsPerSec),
                                     caption: "read + write")
                        }
                    }
                    .frame(width: 260)
                }
            case .explorer:
                SpaceExplorer()
            }
        }
    }

    private var subtitle: String {
        if store.storageTab == .explorer { return "Where the space goes, folder by folder" }
        return "\(store.volumes.count) volume\(store.volumes.count == 1 ? "" : "s") · live I/O since boot"
    }
}

private struct VolumeCard: View {
    @Environment(MonitorStore.self) private var store
    let volume: VolumeInfo

    var body: some View {
        let critical = volume.availableFraction < 0.1
        Card {
            CardHeader(title: volume.name, subtitle: [volume.format, volume.path].filter { !$0.isEmpty }.joined(separator: " · "),
                       symbol: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill", colors: Theme.disk) {
                if volume.isRoot {
                    HStack(spacing: 8) {
                        Button("Space Map") { store.storageTab = .explorer }.buttonStyle(GhostButtonStyle(compact: true))
                        Button { store.page = .cleanup } label: { Label("Clean Up", systemImage: "sparkles") }
                            .buttonStyle(GlowButtonStyle(colors: Theme.cleanup, compact: true))
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BigNumber(value: Fmt.storage(volume.available), size: 30, colors: critical ? Theme.danger : Theme.disk)
                Text("available of \(Fmt.storage(volume.total))").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(Fmt.percent(volume.usedFraction) + " used").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(critical ? Theme.bad : Theme.secondary)
            }
            .padding(.bottom, 12)
            SegmentBar(segments: [
                Segment(id: "used", value: Double(volume.used), color: critical ? Theme.bad : Theme.disk[1]),
                Segment(id: "purgeable", value: Double(volume.purgeable), color: Theme.disk[0].opacity(0.5)),
            ], total: Double(max(1, volume.total)), height: 16)
            .padding(.bottom, 12)
            HStack(spacing: 24) {
                LegendRow(color: critical ? Theme.bad : Theme.disk[1], label: "Used", value: Fmt.storage(volume.used))
                LegendRow(color: Theme.disk[0].opacity(0.5), label: "Purgeable", value: Fmt.storage(volume.purgeable))
                LegendRow(color: Theme.track, label: "Free now", value: Fmt.storage(volume.free))
            }
        }
    }
}

private struct SpaceExplorer: View {
    @Environment(MonitorStore.self) private var store
    @State private var confirming: SpaceNode?

    var body: some View {
        let model = store.space
        if store.access.isRequired, !store.access.hasAccess {
            AccessGate(what: "map your folders")
        } else {
            Card(padding: 0) {
                HStack(spacing: 10) {
                    Breadcrumb()
                    Spacer()
                    if model.phase == .scanning {
                        ProgressView().controlSize(.small)
                        Text("\(model.scanned.formatted()) files · \(Fmt.storage(model.bytesSoFar))")
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                        Button("Stop") { model.cancel() }.buttonStyle(GhostButtonStyle(compact: true))
                    } else {
                        Button("Other Folder…") { model.chooseFolder() }.buttonStyle(GhostButtonStyle(compact: true))
                        Button { model.scan() } label: { Label(model.phase == .done ? "Rescan" : "Scan Home", systemImage: "magnifyingglass") }
                            .buttonStyle(GlowButtonStyle(colors: Theme.disk, compact: true))
                    }
                }
                .padding(16)
                Divider().overlay(Theme.hairline)
                if let current = model.current {
                    let children = current.topChildren()
                    TreemapView(nodes: children, total: current.size, colors: Theme.disk,
                                onOpen: { model.open($0) }, onHover: { model.hovered = $0 })
                        .frame(height: 380)
                        .padding(12)
                    Divider().overlay(Theme.hairline)
                    LazyVStack(spacing: 0) {
                        ForEach(children) { node in
                            SpaceRow(node: node, fraction: current.size > 0 ? Double(node.size) / Double(current.size) : 0,
                                     onTrash: { confirming = node })
                        }
                    }
                    .padding(.vertical, 6)
                } else if model.phase == .idle {
                    EmptyHint(symbol: "chart.pie", title: "Map a folder",
                              detail: "Scans your home folder (or any folder you choose) and shows what takes the space. Apps and bundles count as one item.")
                } else {
                    EmptyHint(symbol: "hourglass", title: "Scanning…", detail: "Large folders take a minute.")
                }
                if let message = model.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
            .confirmationDialog("Move \(confirming?.name ?? "") to the Trash?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
                Button("Move to Trash", role: .destructive) { if let node = confirming { model.trash(node) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(Fmt.storage(confirming?.size ?? 0)) goes to the Trash. You can put it back until you empty the Trash.")
            }
        }
    }

    private struct Breadcrumb: View {
        @Environment(MonitorStore.self) private var store

        var body: some View {
            let chain = store.space.current?.ancestry ?? []
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary) }
                    Button(index == 0 ? abbreviated(node.url.path) : node.name) { store.space.current = node }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: index == chain.count - 1 ? .semibold : .medium))
                        .foregroundStyle(index == chain.count - 1 ? Theme.text : Theme.secondary)
                        .lineLimit(1)
                }
                if chain.isEmpty {
                    Text(abbreviated(store.space.rootURL.path)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                }
            }
        }
    }

    private struct SpaceRow: View {
        @Environment(MonitorStore.self) private var store
        let node: SpaceNode
        let fraction: Double
        let onTrash: () -> Void

        var body: some View {
            HoverRow(accent: Theme.disk[1]) { hovering in
                HStack(spacing: 12) {
                    (node.isDirectory && !node.isPackage ? store.folderIcon() : store.icon(for: node.url.path))
                        .resizable().frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(node.isSummary ? "\(node.fileCount.formatted()) smaller items" : node.name)
                                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer()
                            Text(Fmt.storage(node.size)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        }
                        GeometryReader { geo in
                            Capsule().fill(Theme.track).overlay(alignment: .leading) {
                                Capsule().fill(Theme.disk[1]).frame(width: max(2, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 3)
                    }
                    HStack(spacing: 4) {
                        if node.isDirectory, !node.isPackage, !node.isSummary {
                            IconButton(symbol: "arrow.right", help: "Open \(node.name)") { store.space.open(node) }
                        }
                        if !node.isSummary {
                            IconButton(symbol: "magnifyingglass", help: "Show in Finder") { store.space.reveal(node) }
                            IconButton(symbol: "trash", tint: Theme.tertiary, help: "Move to Trash") { onTrash() }
                        }
                    }
                    .opacity(hovering ? 1 : 0)
                    .frame(width: 92, alignment: .trailing)
                }
            }
            .onTapGesture(count: 2) { store.space.open(node) }
        }
    }
}
