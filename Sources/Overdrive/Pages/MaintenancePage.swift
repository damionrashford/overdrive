import OverdriveCore
import SwiftUI

struct MaintenancePage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        PageScaffold(page: .maintenance, subtitle: store.capabilities.canRunShell
                     ? "One-click fixes. Tasks marked Admin ask for your password through macOS."
                     : "The App Store edition runs without root; the direct edition adds the administrator tasks.") {
            EmptyView()
        } content: {
            if !store.capabilities.canRunShell {
                Notice(symbol: "info.circle", color: Theme.apps[0],
                       text: "Freeing memory, flushing DNS, thinning Time Machine snapshots, rebuilding Spotlight and the Launch Services database need commands the App Sandbox does not allow. They are in the free direct edition on GitHub.") {
                    Link("Get it", destination: Links.repository).font(.system(size: 12, weight: .semibold))
                }
            }
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
                        if task.requiresAdmin { Pill(text: "Admin", color: Theme.warn, symbol: "lock.fill") }
                    }
                    Text(task.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caution = task.caution {
                        Label(caution, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.warn)
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
        .frame(minHeight: 124)
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
