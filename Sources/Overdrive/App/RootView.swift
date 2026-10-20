import OverdriveCore
import SwiftUI

struct RootView: View {
    @Environment(MonitorStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            Sidebar()
            ZStack {
                Backdrop(accent: store.page.accent)
                page
                    .id(store.page)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .animation(.smooth(duration: 0.25), value: store.page)
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .onAppear {
            // Screenshot flag: the Settings scene can only be opened through the environment action.
            if let i = CommandLine.arguments.firstIndex(of: "--show"), CommandLine.arguments.dropFirst(i + 1).first == "settings" {
                openSettings()
            }
        }
        .confirmationDialog(quitTitle, isPresented: Binding(get: { store.pendingQuit != nil },
                                                            set: { if !$0 { store.pendingQuit = nil } })) {
            if let pending = store.pendingQuit {
                Button(pending.force ? "Force Quit" : "Quit", role: .destructive) {
                    store.quit(pending.row, force: pending.force)
                    store.pendingQuit = nil
                }
                if !pending.force {
                    Button("Force Quit") {
                        store.quit(pending.row, force: true)
                        store.pendingQuit = nil
                    }
                }
                Button("Cancel", role: .cancel) { store.pendingQuit = nil }
            }
        } message: {
            if let pending = store.pendingQuit {
                Text(pending.force
                     ? "Unsaved changes in \(pending.row.name) will be lost."
                     : "\(pending.row.name) will be asked to quit and can save its work first.")
            }
        }
    }

    private var quitTitle: String {
        guard let pending = store.pendingQuit else { return "" }
        let suffix = pending.row.count > 1 ? " (\(pending.row.count) processes)" : ""
        return "\(pending.force ? "Force quit" : "Quit") \(pending.row.name)\(suffix)?"
    }

    @ViewBuilder private var page: some View {
        switch store.page {
        case .overview: OverviewPage()
        case .cpu: CPUPage()
        case .memory: MemoryPage()
        case .gpu: GPUPage()
        case .disk: DiskPage()
        case .network: NetworkPage()
        case .battery: BatteryPage()
        case .sensors: SensorsPage()
        case .processes: ProcessesPage()
        case .ai: AIPage()
        case .cleanup: CleanupPage()
        case .apps: AppsPage()
        case .maintenance: MaintenancePage()
        }
    }
}

private struct Sidebar: View {
    @Environment(MonitorStore.self) private var store

    private var monitorPages: [Page] {
        Page.monitor.filter { page in
            switch page {
            case .battery: store.power.hasBattery || store.sampleCount == 0
            case .sensors: store.sensorsAvailable
            default: true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Overdrive").font(Theme.rounded(17, .bold)).foregroundStyle(Theme.text)
                    Text(store.capabilities.isSandboxed ? "App Store edition" : "Direct edition")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.top, 50)
            .padding(.horizontal, 8)
            .padding(.bottom, 22)
            .accessibilityElement(children: .combine)

            SectionLabel(text: "Monitor")
            ForEach(monitorPages) { SidebarItem(page: $0, value: value(for: $0)) }
            SectionLabel(text: "Optimize").padding(.top, 14)
            ForEach(Page.optimize) { SidebarItem(page: $0, value: value(for: $0)) }

            Spacer()
            HealthMini()
                .padding(.bottom, 8)
            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 20)
                    Text("Settings").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text("⌘,").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 228)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Theme.sidebar
                LinearGradient(colors: [store.page.accent[0].opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private func value(for page: Page) -> String? {
        switch page {
        case .overview: "\(store.health.score)"
        case .cpu: Fmt.percent(store.cpu.total)
        case .memory: Fmt.percent(store.memory.usedFraction)
        case .gpu: Fmt.percent(store.gpu.device)
        case .disk: store.rootVolume.map { Fmt.storage($0.available) }
        case .network: Fmt.rate(store.network.downPerSec)
        case .battery: store.power.hasBattery ? Fmt.percent(store.power.percent) : nil
        case .sensors: store.sensors.average(.cpu).map { store.settings.temperature($0) }
        case .processes: "\(store.processes.count)"
        case .ai: store.ai.loaded.isEmpty ? (store.ai.runtimes.isEmpty ? nil : "\(store.ai.runtimes.count)") : Fmt.memory(store.ai.loadedBytes)
        case .cleanup: store.cleanup.phase == .ready ? Fmt.storage(store.cleanup.selectedSize) : nil
        case .apps, .maintenance: nil
        }
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SidebarItem: View {
    @Environment(MonitorStore.self) private var store
    let page: Page
    let value: String?
    @State private var hovering = false

    var body: some View {
        let selected = store.page == page
        Button { store.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(LinearGradient(colors: page.accent, startPoint: .topLeading, endPoint: .bottomTrailing))
                                              : AnyShapeStyle(Theme.secondary))
                    .frame(width: 20)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.secondary)
                Spacer(minLength: 4)
                if let value {
                    Text(value)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(selected ? page.accent[0] : Theme.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [page.accent[0].opacity(0.2), page.accent[1].opacity(0.07)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(page.accent[0].opacity(0.3), lineWidth: 0.8))
                } else if hovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(page.title)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HealthMini: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let report = store.health
        Button { store.page = .overview } label: {
            HStack(spacing: 11) {
                RingGauge(value: Double(report.score) / 100, colors: report.colors, lineWidth: 5, label: "Health score") {
                    Text("\(report.score)").font(Theme.rounded(12, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Health").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    Text(report.label).font(Theme.rounded(14)).foregroundStyle(report.colors[1])
                    Text(report.issues.isEmpty ? "All clear" : "\(report.issues.count) to review")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(CardBackground(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Health \(report.score), \(report.label)")
    }
}

/// The app mark: three nested arcs in the CPU, memory and GPU colors.
struct LogoMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x161A2E), Color(hex: 0x0A0C16)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8))
            ForEach(Array([(Theme.cpu, 0.78, 0.72), (Theme.memory, 0.56, 0.55), (Theme.gpu, 0.34, 0.4)].enumerated()), id: \.offset) { _, ring in
                Circle()
                    .trim(from: 0, to: ring.2)
                    .stroke(LinearGradient(colors: ring.0, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * ring.1, height: size * ring.1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
