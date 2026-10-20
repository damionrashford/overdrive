import OverdriveCore
import SwiftUI

struct DiskPage: View {
    @Environment(MonitorStore.self) private var store

    private let readColor = Color(hex: 0x6EE7B7)
    private let writeColor = Color(hex: 0x38BDF8)

    var body: some View {
        PageScaffold(page: .disk, subtitle: "\(store.volumes.count) volume\(store.volumes.count == 1 ? "" : "s") · live I/O since boot") {
            Button { store.refreshVolumes() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(GhostButtonStyle(compact: true))
        } content: {
            ForEach(store.volumes) { volume in
                VolumeCard(volume: volume)
            }
            if store.volumes.isEmpty {
                Card { EmptyHint(symbol: "internaldrive", title: "Reading volumes…", detail: "") }
            }
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Disk Activity", subtitle: "All physical disks", symbol: "waveform.path.ecg", colors: Theme.disk) {
                        HStack(spacing: 14) {
                            LegendChip(color: readColor, label: "Read")
                            LegendChip(color: writeColor, label: "Write")
                        }
                    }
                    HStack(spacing: 18) {
                        RateLabel(symbol: "arrow.down.doc", color: readColor, label: "Read", value: store.diskIO.readPerSec)
                        RateLabel(symbol: "arrow.up.doc", color: writeColor, label: "Write", value: store.diskIO.writePerSec)
                    }
                    .padding(.bottom, 12)
                    let top = niceCeiling(max(store.diskRead.maxValue, store.diskWrite.maxValue), minimum: 1_000_000)
                    LiveChart(series: [
                        ChartSeries(id: "read", points: store.diskRead.points, color: readColor),
                        ChartSeries(id: "write", points: store.diskWrite.points, color: writeColor),
                    ], xDomain: store.diskRead.xDomain, yMax: top, height: 160, format: { Fmt.rate($0) })
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
        }
    }
}

private struct VolumeCard: View {
    @Environment(MonitorStore.self) private var store
    let volume: VolumeInfo

    var body: some View {
        Card {
            CardHeader(title: volume.name, subtitle: [volume.format, volume.path].filter { !$0.isEmpty }.joined(separator: " · "),
                       symbol: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill", colors: Theme.disk) {
                if volume.isRoot {
                    HStack(spacing: 8) {
                        Button("Reclaim Purgeable") { store.page = .maintenance }
                            .buttonStyle(GhostButtonStyle(compact: true))
                        Button { store.page = .cleanup } label: { Label("Clean Up", systemImage: "sparkles") }
                            .buttonStyle(GlowButtonStyle(colors: Theme.cleanup, compact: true))
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BigNumber(value: Fmt.storage(volume.available), size: 30,
                          colors: volume.availableFraction < 0.1 ? [Color(hex: 0xFCA5A5), Theme.bad] : Theme.disk)
                Text("available of \(Fmt.storage(volume.total))").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Spacer()
                Text(Fmt.percent(volume.usedFraction) + " used").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(volume.availableFraction < 0.1 ? Theme.bad : Theme.secondary)
            }
            .padding(.bottom, 12)
            SegmentBar(segments: [
                Segment(id: "used", value: Double(volume.used), color: volume.availableFraction < 0.1 ? Theme.bad : Theme.disk[1]),
                Segment(id: "purgeable", value: Double(volume.purgeable), color: Theme.disk[0].opacity(0.5)),
            ], total: Double(max(1, volume.total)), height: 16)
            .padding(.bottom, 12)
            HStack(spacing: 24) {
                LegendRow(color: volume.availableFraction < 0.1 ? Theme.bad : Theme.disk[1], label: "Used", value: Fmt.storage(volume.used))
                LegendRow(color: Theme.disk[0].opacity(0.5), label: "Purgeable", value: Fmt.storage(volume.purgeable))
                LegendRow(color: Theme.track, label: "Free now", value: Fmt.storage(volume.free))
            }
        }
    }
}

struct NetworkPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let n = store.network
        PageScaffold(page: .network, subtitle: "Wi-Fi and Ethernet throughput · VPN traffic is not double-counted") {
            EmptyView()
        } content: {
            HStack(spacing: 16) {
                RateCard(symbol: "arrow.down", color: Theme.download, label: "Download", value: n.downPerSec, series: store.netDown)
                RateCard(symbol: "arrow.up", color: Theme.upload, label: "Upload", value: n.upPerSec, series: store.netUp)
            }
            Card {
                CardHeader(title: "Throughput", subtitle: "Scale adapts to recent peaks", symbol: "waveform.path.ecg", colors: Theme.network) {
                    HStack(spacing: 14) {
                        LegendChip(color: Theme.download, label: "Down")
                        LegendChip(color: Theme.upload, label: "Up")
                    }
                }
                let top = niceCeiling(max(store.netDown.maxValue, store.netUp.maxValue), minimum: 100_000)
                LiveChart(series: [
                    ChartSeries(id: "down", points: store.netDown.points, color: Theme.download),
                    ChartSeries(id: "up", points: store.netUp.points, color: Theme.upload),
                ], xDomain: store.netDown.xDomain, yMax: top, height: 210, format: { Fmt.rate($0) })
            }
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Since Boot", symbol: "clock.arrow.circlepath", colors: Theme.network)
                    HStack(alignment: .top) {
                        StatTile(label: "Downloaded", value: Fmt.storage(n.totalDown))
                        StatTile(label: "Uploaded", value: Fmt.storage(n.totalUp))
                    }
                }
                .frame(width: 300)
                Card {
                    CardHeader(title: "Interfaces", subtitle: "Active, with an IPv4 address", symbol: "point.3.connected.trianglepath.dotted",
                               colors: Theme.network)
                    if n.interfaces.isEmpty {
                        EmptyHint(symbol: "wifi.slash", title: "Offline", detail: "No interface has an address.")
                    }
                    VStack(spacing: 10) {
                        ForEach(n.interfaces) { iface in
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: iface))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.network[0])
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Theme.network[0].opacity(0.12)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(iface.displayName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                                    Text("\(iface.bsdName) · \(iface.ipv4 ?? "no address")")
                                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("↓ \(Fmt.storage(iface.bytesIn))").font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Theme.secondary)
                                    Text("↑ \(Fmt.storage(iface.bytesOut))").font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Theme.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func icon(for iface: NetworkInterfaceInfo) -> String {
        let name = iface.displayName.lowercased()
        if name.contains("wi-fi") { return "wifi" }
        if iface.bsdName.hasPrefix("utun") { return "lock.shield" }
        if name.contains("thunderbolt") { return "bolt.horizontal" }
        return "cable.connector"
    }
}

private struct RateCard: View {
    let symbol: String
    let color: Color
    let label: String
    let value: Double
    let series: Series

    var body: some View {
        Card(highlight: color.opacity(0.5)) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(color.opacity(0.14)))
                    .shadow(color: color.opacity(0.5), radius: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.tertiary)
                    BigNumber(value: Fmt.rate(value), size: 30)
                }
                Spacer()
                Text("peak \(Fmt.rate(series.maxValue))").font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}
