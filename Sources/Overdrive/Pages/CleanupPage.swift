import OverdriveCore
import SwiftUI

struct CleanupPage: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        PageScaffold(page: .cleanup, subtitle: subtitle) {
            SegmentedTabs(selection: $store.cleanupTab, options: [(.junk, "Junk"), (.large, "Large Files")], colors: Theme.cleanup)
        } content: {
            switch store.cleanupTab {
            case .junk: JunkView()
            case .large: LargeFilesView()
            }
        }
    }

    private var subtitle: String {
        if let root = store.rootVolume { return "\(Fmt.storage(root.available)) available on \(root.name)" }
        return "Reclaim space safely"
    }
}

// MARK: - Junk

private struct JunkView: View {
    @Environment(MonitorStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let model = store.cleanup
        switch model.phase {
        case .idle:
            Card(highlight: Theme.cleanup[0].opacity(0.5)) {
                VStack(spacing: 14) {
                    IconBadge(symbol: "sparkles", colors: Theme.cleanup, size: 64)
                        .shadow(color: Theme.cleanup[1].opacity(0.5), radius: 20)
                    Text("Find reclaimable space").font(Theme.rounded(22, .bold)).foregroundStyle(Theme.text)
                    Text("Scans app caches, logs, developer build products, package caches, the Trash and stale downloads. Nothing is removed until you review it.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                    Button { Task { await model.scan() } } label: { Label("Scan My Mac", systemImage: "magnifyingglass") }
                        .buttonStyle(GlowButtonStyle(colors: Theme.cleanup))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
        case .scanning:
            Card {
                VStack(spacing: 14) {
                    ProgressView(value: Double(model.measured), total: Double(max(1, model.itemCount)))
                        .tint(Theme.cleanup[0])
                        .frame(maxWidth: 360)
                    Text("Measuring \(model.measured) of \(model.itemCount) locations…")
                        .font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Theme.secondary)
                    Text("Found \(Fmt.storage(model.totalSize)) so far").font(Theme.rounded(20, .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: Theme.cleanup, startPoint: .leading, endPoint: .trailing))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        case .ready, .cleaning, .done:
            summary(model)
            if model.groups.isEmpty {
                Card { EmptyHint(symbol: "checkmark.seal", title: "Spotless", detail: "Nothing left to clean.") }
            }
            ForEach(model.groups) { group in
                CategoryCard(groupID: group.id)
            }
        }
    }

    @ViewBuilder
    private func summary(_ model: CleanupModel) -> some View {
        Card(highlight: Theme.cleanup[0].opacity(0.5)) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    if model.phase == .done {
                        Label(model.freed > 0 ? "Freed \(Fmt.storage(model.freed))" : "Done",
                              systemImage: "checkmark.circle.fill")
                            .font(Theme.rounded(22, .bold)).foregroundStyle(Theme.good)
                        if model.trashed > 0 {
                            Text("\(Fmt.storage(model.trashed)) moved to the Trash. Empty it to free that space too.")
                                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        if !model.failures.isEmpty {
                            Text("\(model.failures.count) item\(model.failures.count == 1 ? "" : "s") were in use or protected and were skipped.")
                                .font(.system(size: 12)).foregroundStyle(Theme.warn)
                                .help(model.failures.prefix(12).joined(separator: "\n"))
                        }
                    } else {
                        Text("SELECTED").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.tertiary)
                        BigNumber(value: Fmt.storage(model.selectedSize), size: 32, colors: Theme.cleanup)
                        Text("of \(Fmt.storage(model.totalSize)) found · \(model.selectedCount) items")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.phase == .cleaning)
                if model.phase != .done || model.selectedCount > 0 {
                    Button { confirming = true } label: {
                        HStack(spacing: 6) {
                            if model.phase == .cleaning { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "sparkles") }
                            Text(model.phase == .cleaning ? "Cleaning…" : "Clean \(Fmt.storage(model.selectedSize))")
                        }
                    }
                    .buttonStyle(GlowButtonStyle(colors: Theme.cleanup))
                    .disabled(model.selectedCount == 0 || model.phase == .cleaning)
                }
            }
        }
        .confirmationDialog("Clean \(Fmt.storage(model.selectedSize))?", isPresented: $confirming) {
            Button("Clean \(model.selectedCount) Items", role: .destructive) { Task { await model.clean() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.selectedTrashCount > 0
                 ? "Caches and logs are deleted permanently. \(model.selectedTrashCount) download(s) go to the Trash."
                 : "Selected caches, logs and build products are deleted permanently. Apps rebuild them as needed.")
        }
    }
}

private struct CategoryCard: View {
    @Environment(MonitorStore.self) private var store
    let groupID: String

    var body: some View {
        let model = store.cleanup
        if let group = model.groups.first(where: { $0.id == groupID }) {
            let all = group.selectedCount == group.entries.count
            Card(padding: 0) {
                HStack(spacing: 12) {
                    Checkbox(isOn: Binding(get: { all }, set: { model.setAll($0, in: groupID) }),
                             mixed: group.selectedCount > 0)
                    IconBadge(symbol: group.category.symbol, colors: Theme.cleanup, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.category.title).font(Theme.rounded(14.5)).foregroundStyle(Theme.text)
                        Text(group.category.subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.storage(group.total)).font(Theme.rounded(15)).monospacedDigit().foregroundStyle(Theme.text)
                        Text("\(group.selectedCount)/\(group.entries.count) selected").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(group.expanded ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { model.toggleExpanded(groupID) } }

                if group.expanded {
                    Divider().overlay(Theme.hairline)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Bindings resolve by id: positions shift when cleaning removes entries.
                            ForEach(group.entries) { entry in
                                EntryRow(entry: entry, isOn: Binding(
                                    get: { model.isSelected(entry.id) },
                                    set: { model.setSelected(entry.id, $0) }))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(height: min(CGFloat(group.entries.count) * 41 + 12, 420))
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: CleanupModel.Entry
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Checkbox(isOn: $isOn)
            CleanupModel.icon(for: entry).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(entry.item.note ?? (entry.item.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if hovering {
                IconButton(symbol: "folder", help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.item.url])
                }
            }
            Text(Fmt.storage(entry.size ?? 0)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondary).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.leading, 30)
        .padding(.vertical, 6)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - Large files

private struct LargeFilesView: View {
    @Environment(MonitorStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let model = store.largeFiles
        Card {
            HStack(spacing: 14) {
                IconBadge(symbol: "doc.viewfinder", colors: Theme.cleanup, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Large files in your home folder").font(Theme.rounded(14.5)).foregroundStyle(Theme.text)
                    Text("Skips Library, the Trash, node_modules, .git and mounted drives.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Picker("", selection: Binding(get: { model.threshold }, set: { model.threshold = $0 })) {
                    ForEach(LargeFilesModel.thresholds, id: \.self) { t in Text("≥ \(Fmt.storage(t))").tag(t) }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(model.phase == .scanning)
                if model.phase == .scanning {
                    Button("Stop") { model.cancel() }.buttonStyle(GhostButtonStyle())
                } else {
                    Button { model.scan() } label: { Label(model.phase == .done ? "Rescan" : "Scan", systemImage: "magnifyingglass") }
                        .buttonStyle(GlowButtonStyle(colors: Theme.cleanup))
                }
            }
            if model.phase == .scanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Scanned \(model.scanned.formatted()) files…").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                }
                .padding(.top, 14)
            }
        }

        if model.phase == .done {
            Card(padding: 0) {
                HStack {
                    Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s") · \(Fmt.storage(model.files.reduce(0) { $0 + $1.size }))")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    if model.trashedBytes > 0 {
                        Text("· \(Fmt.storage(model.trashedBytes)) moved to Trash").font(.system(size: 12)).foregroundStyle(Theme.good)
                    }
                    Spacer()
                    Button("Show in Finder") { model.reveal(model.files.filter { model.selection.contains($0.id) }) }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .disabled(model.selection.isEmpty)
                    Button("Move \(Fmt.storage(model.selectedSize)) to Trash") { confirming = true }
                        .buttonStyle(GlowButtonStyle(colors: Theme.cleanup, compact: true))
                        .disabled(model.selection.isEmpty)
                }
                .padding(16)
                if let error = model.lastError {
                    Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.warn).padding(.horizontal, 16).padding(.bottom, 10)
                }
                Divider().overlay(Theme.hairline)
                if model.files.isEmpty {
                    EmptyHint(symbol: "checkmark.seal", title: "No files that big",
                              detail: "Nothing over \(Fmt.storage(model.threshold)) outside Library.")
                }
                if !model.files.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.files) { file in
                                LargeFileRow(file: file, isOn: Binding(
                                    get: { model.selection.contains(file.id) },
                                    set: { if $0 { model.selection.insert(file.id) } else { model.selection.remove(file.id) } }))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(height: min(CGFloat(model.files.count) * 45 + 12, 520))
                }
            }
            .confirmationDialog("Move \(model.selection.count) file(s) to the Trash?", isPresented: $confirming) {
                Button("Move to Trash", role: .destructive) { model.trashSelected() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(Fmt.storage(model.selectedSize)) will go to the Trash. You can put them back until you empty it.")
            }
        }
    }
}

private struct LargeFileRow: View {
    @Environment(MonitorStore.self) private var store
    let file: LargeFile
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Checkbox(isOn: $isOn)
            (store.icon(for: file.url.path)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text((file.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let date = file.modified {
                Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
            IconButton(symbol: "magnifyingglass", help: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            .opacity(hovering ? 1 : 0)
            Text(Fmt.storage(file.size)).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.text).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { isOn.toggle() }
    }
}
