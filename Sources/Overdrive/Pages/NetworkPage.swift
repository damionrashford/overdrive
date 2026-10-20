import OverdriveCore
import SwiftUI

struct NetworkPage: View {
    @Environment(MonitorStore.self) private var store
    @State private var publicIP: String?
    @State private var lookingUp = false

    var body: some View {
        @Bindable var settings = store.settings
        let n = store.network
        let range = store.settings.chartRange
        PageScaffold(page: .network, subtitle: "Wi‑Fi and Ethernet throughput · VPN traffic is not double-counted") {
            EmptyView()
        } content: {
            HStack(spacing: 16) {
                RateCard(symbol: "arrow.down", color: Theme.download, label: "Download", value: n.downPerSec, series: store.netDown[range])
                RateCard(symbol: "arrow.up", color: Theme.upload, label: "Upload", value: n.upPerSec, series: store.netUp[range])
            }
            Card {
                HistoryHeader(title: "Throughput", subtitle: "Scale adapts to recent peaks", colors: Theme.network) {
                    LegendChip(color: Theme.download, label: "Down")
                    LegendChip(color: Theme.upload, label: "Up")
                }
                let top = niceCeiling(max(store.netDown[range].maxValue, store.netUp[range].maxValue), minimum: 100_000)
                LiveChart(series: [
                    ChartSeries(id: "Down", series: store.netDown[range], color: Theme.download),
                    ChartSeries(id: "Up", series: store.netUp[range], color: Theme.upload),
                ], xDomain: store.netDown[range].xDomain, yMax: top, height: 210, label: "Network throughput", format: { Fmt.rate($0) })
            }
            HStack(alignment: .top, spacing: 16) {
                Card {
                    CardHeader(title: "Since Boot", symbol: "clock.arrow.circlepath", colors: Theme.network)
                    HStack(alignment: .top) {
                        StatTile(label: "Downloaded", value: Fmt.storage(n.totalDown))
                        StatTile(label: "Uploaded", value: Fmt.storage(n.totalUp))
                    }
                    Divider().overlay(Theme.hairline).padding(.vertical, 14)
                    HStack(spacing: 10) {
                        Toggle("Show public IP", isOn: $settings.showPublicIP).toggleStyle(.switch).controlSize(.small)
                            .font(.system(size: 12.5)).foregroundStyle(Theme.text)
                        Spacer()
                        if settings.showPublicIP {
                            if lookingUp {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(publicIP ?? "–").font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                                    .textSelection(.enabled)
                                IconButton(symbol: "arrow.clockwise", help: "Look up again") { Task { await lookup() } }
                            }
                        }
                    }
                    Text("Off by default. Turning it on makes one request to api.ipify.org, the only network call Overdrive ever makes.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary).padding(.top, 6)
                }
                .frame(width: 340)
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
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .task(id: store.settings.showPublicIP) {
            if store.settings.showPublicIP, publicIP == nil { await lookup() }
        }
    }

    private func lookup() async {
        lookingUp = true
        defer { lookingUp = false }
        guard let url = URL(string: "https://api64.ipify.org?format=json") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let ip = json["ip"] as? String {
            publicIP = ip
        } else {
            publicIP = "Unavailable"
        }
    }

    private func icon(for iface: NetworkInterfaceInfo) -> String {
        let name = iface.displayName.lowercased()
        if name.contains("wi-fi") || name.contains("wi‑fi") { return "wifi" }
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Card(highlight: color.opacity(0.5)) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(color.opacity(0.14)))
                    .shadow(color: color.opacity(scheme == .dark ? 0.5 : 0.2), radius: 12)
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
