import OverdriveCore
import SwiftUI

struct AppsPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        PageScaffold(page: .apps, subtitle: subtitle, scrolls: store.appsTab == .startup) {
            SegmentedTabs(selection: $store.appsTab, options: [(.installed, "Installed"), (.startup, "Startup Items")], colors: Theme.apps)
        } content: {
            if store.access.isRequired, !store.access.hasAccess {
                AccessGate(what: "find the files apps leave behind")
            } else {
                switch store.appsTab {
                case .installed: InstalledAppsView()
                case .startup: StartupItemsView()
                }
            }
        }
        .task {
            if store.apps.apps.isEmpty { await store.apps.loadApps() }
            if !store.apps.startupLoaded { await store.apps.loadStartup() }
        }
    }

    private var subtitle: String {
        switch store.appsTab {
        case .installed:
            let total = store.apps.apps.compactMap(\.size).reduce(0, +)
            return "\(store.apps.apps.count) apps · \(Fmt.storage(total))\(store.apps.measured < store.apps.apps.count ? " so far" : "")"
        case .startup:
            return "\(store.apps.startupItems.count) launchd items · what runs without you asking"
        }
    }
}

// MARK: - Installed apps and leftovers

private struct InstalledAppsView: View {
    @Environment(MonitorStore.self) private var store
    @State private var query = ""
    @State private var confirming = false

    var body: some View {
        let model = store.apps
        let apps = model.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        HStack(alignment: .top, spacing: 16) {
            Card(padding: 0) {
                HStack {
                    SearchField(text: $query, prompt: "Filter apps")
                    Spacer()
                    if model.loadingApps { ProgressView().controlSize(.small) }
                    Text("\(apps.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
                .padding(14)
                Divider().overlay(Theme.hairline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps) { app in
                            AppRow(app: app, selected: model.selected?.id == app.id)
                                .onTapGesture { Task { await model.select(model.selected?.id == app.id ? nil : app) } }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 400)

            Card {
                if let app = model.selected {
                    LeftoversView(app: app, confirming: $confirming)
                } else {
                    EmptyHint(symbol: "square.stack.3d.up", title: "Select an app",
                              detail: "Overdrive lists every file the app leaves in Library folders before anything is moved to the Trash.")
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .confirmationDialog("Move \(model.selected?.name ?? "app") to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { Task { await model.uninstall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.includeApp ? "The app and " : "")\(model.selection.count) leftover item(s), \(Fmt.storage(model.selectedLeftoverBytes + (model.includeApp ? model.selected?.size ?? 0 : 0))) in total, go to the Trash. You can put them back until you empty it.")
        }
    }

    private struct AppRow: View {
        @Environment(MonitorStore.self) private var store
        let app: InstalledApp
        let selected: Bool

        var body: some View {
            HoverRow(selected: selected, accent: Theme.apps[1]) { _ in
                HStack(spacing: 10) {
                    store.icon(for: app.url.path).resizable().frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text([app.version.map { "v\($0)" }, app.lastUsed.map { "opened \($0.formatted(.relative(presentation: .named)))" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                    Spacer()
                    Text(app.size.map(Fmt.storage) ?? "…").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

private struct LeftoversView: View {
    @Environment(MonitorStore.self) private var store
    let app: InstalledApp
    @Binding var confirming: Bool

    var body: some View {
        let model = store.apps
        let running = model.isRunning(app)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                store.icon(for: app.url.path).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(Theme.rounded(18, .bold)).foregroundStyle(Theme.text)
                    Text([app.bundleID, app.version.map { "Version \($0)" }, app.size.map(Fmt.storage)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text(abbreviated(app.url.path)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                if running {
                    Button("Quit App") { model.quit(app) }.buttonStyle(GhostButtonStyle(compact: true))
                        .disabled(!store.capabilities.canQuitProcesses)
                }
                IconButton(symbol: "folder", help: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            }
            .padding(.bottom, 14)

            if app.isSystem {
                Notice(symbol: "lock.fill", color: Theme.warn, text: "Apple’s own apps are protected by macOS and cannot be removed.")
                    .padding(.bottom, 12)
            } else if running {
                Notice(symbol: "exclamationmark.circle", color: Theme.warn,
                       text: store.capabilities.canQuitProcesses ? "\(app.name) is running. Quit it before uninstalling." : "\(app.name) is running. Quit it (⌘Q in the app) before uninstalling.")
                    .padding(.bottom, 12)
            }

            HStack {
                Text("LEFTOVERS").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.tertiary)
                if model.findingLeftovers { ProgressView().controlSize(.mini) }
                Spacer()
                Text("\(Fmt.storage(model.selectedLeftoverBytes)) selected").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            .padding(.bottom, 6)

            if model.leftovers.isEmpty, !model.findingLeftovers {
                Text("No files found outside the app bundle.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary).padding(.vertical, 10)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.leftovers) { item in
                        HoverRow { hovering in
                            HStack(spacing: 10) {
                                Checkbox(isOn: Binding(get: { model.selection.contains(item.id) },
                                                       set: { if $0 { model.selection.insert(item.id) } else { model.selection.remove(item.id) } }),
                                         color: Theme.apps[1], label: item.url.lastPathComponent)
                                    .disabled(item.requiresAdmin)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.url.lastPathComponent).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(item.kind.rawValue + (item.requiresAdmin ? " · needs an administrator" : "") + " · " + abbreviated(item.url.deletingLastPathComponent().path))
                                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if hovering {
                                    IconButton(symbol: "folder", help: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                }
                                Text(Fmt.storage(item.size)).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.secondary)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, -16)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(Theme.hairline).padding(.vertical, 12)
            if let outcome = model.outcome {
                Notice(symbol: outcome.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                       color: outcome.failures.isEmpty ? Theme.good : Theme.warn,
                       text: outcome.failures.isEmpty
                           ? "Moved \(outcome.trashed.count) item(s), \(Fmt.storage(outcome.bytes)), to the Trash."
                           : "Moved \(outcome.trashed.count) item(s); \(outcome.failures.count) could not be moved (\(outcome.failures.first ?? "")).")
                    .padding(.bottom, 10)
            }
            HStack {
                Toggle("Also move the app itself", isOn: Binding(get: { model.includeApp }, set: { model.includeApp = $0 }))
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                    .disabled(app.isSystem)
                Spacer()
                Button { confirming = true } label: { Label(model.includeApp ? "Uninstall" : "Remove Leftovers", systemImage: "trash") }
                    .buttonStyle(GlowButtonStyle(colors: Theme.danger))
                    .disabled(app.isSystem || (running && model.includeApp) || (model.selection.isEmpty && !model.includeApp))
            }
        }
    }
}

// MARK: - Startup items

private struct StartupItemsView: View {
    @Environment(MonitorStore.self) private var store
    @State private var confirming: StartupItem?

    var body: some View {
        let model = store.apps
        Card {
            HStack(spacing: 12) {
                IconBadge(symbol: "power", colors: Theme.apps, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Login items and background agents").font(Theme.rounded(14.5)).foregroundStyle(Theme.text)
                    Text("launchd job definitions on disk. Apple’s own are listed for completeness; third-party ones are what slow down login.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Button("Login Items Settings…") { model.openLoginItemsSettings() }.buttonStyle(GhostButtonStyle(compact: true))
                Button { Task { await model.loadStartup() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
            if let message = model.startupMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.top, 10)
            }
        }
        ForEach([StartupItem.Scope.userAgent, .globalAgent, .daemon], id: \.self) { scope in
            let items = model.startupItems.filter { $0.scope == scope }
            if !items.isEmpty {
                Card(padding: 0) {
                    HStack {
                        Text(title(for: scope)).font(Theme.rounded(14)).foregroundStyle(Theme.text)
                        Text(path(for: scope)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        Spacer()
                        Text("\(items.filter { !$0.isApple }.count) third-party · \(items.count) total").font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    }
                    .padding(16)
                    Divider().overlay(Theme.hairline)
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            StartupRow(item: item) { confirming = item }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .confirmationDialog("Move \(confirming?.url.lastPathComponent ?? "") to the Trash?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Move to Trash", role: .destructive) { if let item = confirming { model.trashStartup(item) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The job will not start at your next login. The app that installed it may recreate it when it next runs.")
        }
    }

    private func title(for scope: StartupItem.Scope) -> String {
        switch scope {
        case .userAgent: "Your login"
        case .globalAgent: "Every user’s login"
        case .daemon: "System daemons"
        }
    }

    private func path(for scope: StartupItem.Scope) -> String {
        switch scope {
        case .userAgent: "~/Library/LaunchAgents"
        case .globalAgent: "/Library/LaunchAgents"
        case .daemon: "/Library/LaunchDaemons"
        }
    }

    private struct StartupRow: View {
        @Environment(MonitorStore.self) private var store
        let item: StartupItem
        let onTrash: () -> Void

        var body: some View {
            let model = store.apps
            HoverRow { hovering in
                HStack(spacing: 12) {
                    Image(systemName: item.isApple ? "apple.logo" : "gearshape.2")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(item.isApple ? Theme.tertiary : Theme.apps[0])
                        .frame(width: 26, height: 26).background(Circle().fill(Theme.fill))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(item.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(item.isApple ? Theme.secondary : Theme.text).lineLimit(1)
                            if item.disabled == true { Pill(text: "Disabled", color: Theme.tertiary) }
                            if item.keepAlive { Pill(text: "Keeps running", color: Theme.warn) }
                        }
                        Text([item.runAtLoad ? "at login" : nil, item.interval.map { "every \(Fmt.duration(Double($0)))" }, item.program]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if hovering {
                        IconButton(symbol: "folder", help: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                        if !item.isApple, item.scope == .userAgent {
                            IconButton(symbol: "trash", tint: Theme.tertiary, help: "Move to Trash") { onTrash() }
                        }
                    }
                    if store.capabilities.canRunShell, !item.isApple {
                        Toggle("", isOn: Binding(get: { item.disabled != true }, set: { enabled in Task { await model.setStartup(item, enabled: enabled) } }))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                            .accessibilityLabel("Enabled")
                    }
                }
            }
        }
    }
}
