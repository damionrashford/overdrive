import OverdriveCore
import SwiftUI

struct MaintenancePage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        PageScaffold(page: .maintenance, subtitle: "One-click fixes. Tasks marked Admin ask for your password through macOS.") {
            EmptyView()
        } content: {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(store.maintenance.tasks) { task in
                    TaskCard(task: task)
                }
            }
        }
    }
}

private struct TaskCard: View {
    @Environment(MonitorStore.self) private var store
    let task: MaintenanceTask
    @State private var confirming = false

    var body: some View {
        let state = store.maintenance.state(task.id)
        Card(highlight: state == .running ? Theme.maintenance[0] : nil) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: task.symbol, colors: Theme.maintenance, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(task.title).font(Theme.rounded(14.5)).foregroundStyle(Theme.text)
                        if task.requiresAdmin {
                            Pill(text: "Admin", color: Theme.warn, symbol: "lock.fill").scaleEffect(0.85)
                        }
                    }
                    Text(task.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caution = task.caution {
                        Label(caution, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.warn.opacity(0.85))
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 14)
            HStack {
                TaskStatusLine(state: state)
                if state == .idle, let date = store.maintenance.lastRun[task.id] {
                    Text("Last run \(date.formatted(.relative(presentation: .named)))").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Button {
                    if task.caution != nil { confirming = true } else { run() }
                } label: {
                    HStack(spacing: 6) {
                        if state == .running { ProgressView().controlSize(.small).tint(.white) }
                        Text(state == .running ? "Running" : "Run")
                    }
                }
                .buttonStyle(GlowButtonStyle(colors: Theme.maintenance, compact: true))
                .disabled(state == .running)
            }
        }
        .frame(minHeight: 150)
        .confirmationDialog("\(task.title)?", isPresented: $confirming) {
            Button(task.title, role: .destructive) { run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(task.detail) \(task.caution.map { "\($0)." } ?? "")")
        }
    }

    private func run() {
        Task { await store.maintenance.run(task) }
    }
}

struct SettingsPage: View {
    @Environment(MonitorStore.self) private var store
    @State private var launchAtLogin = MonitorStore.shared.launchAtLogin
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        PageScaffold(page: .settings, subtitle: "Overdrive \(Bundle.main.shortVersion) · everything stays on this Mac") {
            EmptyView()
        } content: {
            Card {
                CardHeader(title: "Monitoring", symbol: "waveform.path.ecg", colors: Theme.settings)
                SettingRow(title: "Refresh every", detail: "Faster updates use slightly more energy.") {
                    SegmentedTabs(selection: $store.refreshInterval, options: [(1.0, "1 s"), (2.0, "2 s"), (5.0, "5 s")],
                                  colors: Theme.cpu)
                }
            }
            Card {
                CardHeader(title: "Menu Bar", symbol: "menubar.rectangle", colors: Theme.settings)
                SettingRow(title: "Show in menu bar", detail: "Click the menu bar item for a live mini dashboard.") {
                    SegmentedTabs(selection: $store.menuBarStyle, options: MenuBarStyle.allCases.map { ($0, $0.label) },
                                  colors: Theme.cpu)
                }
            }
            Card {
                CardHeader(title: "General", symbol: "switch.2", colors: Theme.settings)
                SettingRow(title: "Open at login", detail: loginError ?? "Start Overdrive in the menu bar when you log in.") {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { newValue in
                        loginError = store.setLaunchAtLogin(newValue)
                        launchAtLogin = store.launchAtLogin
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.cpu[1])
                }
            }
            Card {
                CardHeader(title: "This Mac", symbol: "laptopcomputer", colors: Theme.settings)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        StatTile(label: "Model", value: store.info.modelName, caption: store.info.modelIdentifier)
                        StatTile(label: "Chip", value: store.info.chip, caption: store.info.coreSummary)
                    }
                    GridRow {
                        StatTile(label: "Memory", value: Fmt.memory(store.info.physicalMemory))
                        StatTile(label: "macOS", value: store.info.osVersion, caption: "Build \(store.info.osBuild)")
                    }
                }
                Text("Overdrive makes no network requests and collects nothing. Metrics are read from the kernel and IORegistry on this Mac.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary).padding(.top, 14)
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            control()
        }
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
}
