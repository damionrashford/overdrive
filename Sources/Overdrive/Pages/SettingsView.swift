import OverdriveCore
import SwiftUI

/// The Settings window (⌘,), with the standard macOS tab toolbar.
struct SettingsView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettings().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            AlertSettings().tabItem { Label("Alerts", systemImage: "bell.badge") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
        .environment(store)
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 4)
    }
}

private struct GeneralSettings: View {
    @Environment(MonitorStore.self) private var store
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Monitoring") {
                SettingRow(title: "Refresh every", detail: "Faster updates cost a little more energy.") {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                    }
                    .labelsHidden().frame(width: 130)
                }
                SettingRow(title: "Default chart range") {
                    Picker("", selection: $settings.chartRange) {
                        ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                }
                SettingRow(title: "Temperature unit") {
                    Picker("", selection: $settings.useFahrenheit) {
                        Text("Celsius").tag(false)
                        Text("Fahrenheit").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
                SettingRow(title: "Overdrive’s own cost",
                           detail: "What this app is using right now, so you can judge it.") {
                    Text(String(format: "%.1f%% CPU · %@", store.selfCPU, Fmt.memory(store.selfMemory)))
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Section("Startup") {
                SettingRow(title: "Open at login", detail: loginError ?? "Keeps the menu bar readout available after a restart.") {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { newValue in
                        loginError = store.setLaunchAtLogin(newValue)
                        launchAtLogin = store.launchAtLogin
                    }))
                    .toggleStyle(.switch).labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = store.launchAtLogin }
    }
}

private struct MenuBarSettings: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Menu bar item") {
                SettingRow(title: "Style") {
                    Picker("", selection: $settings.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                ForEach(MenuBarModule.allCases) { module in
                    if module != .temperature || store.sensorsAvailable {
                        Toggle(module.label, isOn: Binding(
                            get: { settings.menuBarModules.contains(module) },
                            set: { on in
                                if on { if !settings.menuBarModules.contains(module) { settings.menuBarModules.append(module) } }
                                else { settings.menuBarModules.removeAll { $0 == module } }
                            }))
                        .disabled(settings.menuBarStyle == .icon)
                    }
                }
                Text("Click the item for the live mini dashboard. macOS may hide menu bar items when the bar is full; System Settings › Menu Bar controls which ones show.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertSettings: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").font(.system(size: 13))
                        Text(authorizationText).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.alerts.authorization != .granted {
                        Button("Allow Notifications") { store.alerts.requestAuthorization() }
                    }
                }
            }
            Section("Rules") {
                ForEach(AlertKind.allCases) { kind in
                    if kind != .temperature || store.sensorsAvailable, kind != .battery || store.power.hasBattery {
                        RuleRow(kind: kind)
                    }
                }
                Text("Each rule notifies at most once every 15 minutes.").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.alerts.refreshAuthorization() }
    }

    private var authorizationText: String {
        switch store.alerts.authorization {
        case .granted: "Allowed. Alerts appear as macOS notifications."
        case .denied: "Turned off in System Settings › Notifications › Overdrive."
        case .unknown: "Not yet allowed."
        }
    }

    private struct RuleRow: View {
        @Environment(MonitorStore.self) private var store
        let kind: AlertKind

        var body: some View {
            let rule = store.settings.rule(kind)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(get: { rule.enabled }, set: { var r = rule; r.enabled = $0; store.settings.update(r) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(kind.title).font(.system(size: 13))
                            if store.alerts.active.contains(kind) { Text("firing").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.warn) }
                        }
                        Text(kind.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                if rule.enabled, kind.hasThreshold {
                    HStack(spacing: 12) {
                        Text("Threshold").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { rule.threshold }, set: { var r = rule; r.threshold = $0; store.settings.update(r) }),
                               in: kind.thresholdRange, step: kind.step)
                        Text("\(Int(rule.threshold))\(kind.unit)").font(.system(size: 11.5).monospacedDigit()).frame(width: 52, alignment: .trailing)
                        if kind.hasDuration {
                            Picker("", selection: Binding(get: { rule.sustainedSeconds }, set: { var r = rule; r.sustainedSeconds = $0; store.settings.update(r) })) {
                                Text("30 s").tag(30.0)
                                Text("1 min").tag(60.0)
                                Text("2 min").tag(120.0)
                                Text("5 min").tag(300.0)
                            }
                            .labelsHidden().frame(width: 90)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
        }
    }
}

private struct PrivacySettings: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Data") {
                Text("Overdrive reads metrics from the kernel and IORegistry on this Mac. It has no account, no analytics and no crash reporting. The only optional network request is the public IP lookup on the Network page, off by default.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Link("Read the privacy policy", destination: Links.privacy).font(.system(size: 12))
            }
            if store.access.isRequired {
                Section("Folder access") {
                    SettingRow(title: "Home folder",
                               detail: store.access.grantedURL.map { "Granted: \(abbreviated($0.path))" } ?? "Not granted. Cleanup, Apps and the storage map need it.") {
                        if store.access.hasAccess {
                            Button("Revoke") { store.access.revoke() }
                        } else {
                            Button("Choose…") { store.access.requestAccess() }
                        }
                    }
                }
            }
            Section("Cleanup exclusions") {
                if settings.cleanupExclusions.isEmpty {
                    Text("Nothing ignored. Use the eye button on a cleanup item to keep it out of future scans.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(settings.cleanupExclusions.sorted(), id: \.self) { path in
                    HStack {
                        Text(abbreviated(path)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { settings.cleanupExclusions.remove(path) }.controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    LogoMark(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Overdrive \(Bundle.main.shortVersion)").font(.system(size: 15, weight: .semibold))
                        Text("Build \(Bundle.main.buildNumber) · \(store.capabilities.editionName)").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("Free and open source, MIT license.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("This Mac") {
                LabeledContent("Model", value: "\(store.info.modelName) (\(store.info.modelIdentifier))")
                LabeledContent("Chip", value: "\(store.info.chip) · \(store.info.coreSummary)")
                LabeledContent("GPU", value: store.info.gpuName + (store.info.gpuCores.map { " · \($0) cores" } ?? ""))
                LabeledContent("Memory", value: Fmt.memory(store.info.physicalMemory))
                LabeledContent("macOS", value: "\(store.info.osVersion) (\(store.info.osBuild))")
            }
            Section {
                Link("Source code on GitHub", destination: Links.repository)
                Link("Report a problem", destination: Links.issues)
                Button("Copy System Report") { Report.copy(store: store) }
            }
        }
        .formStyle(.grouped)
    }
}
