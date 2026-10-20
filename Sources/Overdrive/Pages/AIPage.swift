import OverdriveCore
import SwiftUI

struct AIPage: View {
    @Environment(MonitorStore.self) private var store
    @State private var confirmingOrphans = false

    var body: some View {
        let ai = store.ai
        PageScaffold(page: .ai, subtitle: subtitle) {
            if let version = ai.ollamaVersion { Pill(text: "Ollama \(version)", color: Theme.ai[0], symbol: "checkmark.circle") }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                RuntimesCard()
                HeadroomCard()
            }
            .fixedSize(horizontal: false, vertical: true)

            if !ai.loaded.isEmpty {
                LoadedModelsCard()
            }

            if store.access.isRequired, !store.access.hasAccess {
                AccessGate(what: "measure your model libraries")
            } else {
                ModelLibraryCard(confirmingOrphans: $confirmingOrphans)
            }
        }
        .task { if ai.storesScannedAt == nil { await ai.scanStores() } }
        .confirmationDialog("Delete \(Fmt.storage(ai.orphanBytes)) of orphaned Ollama blobs?", isPresented: $confirmingOrphans) {
            Button("Delete \(ai.orphans.count) Blobs", role: .destructive) { Task { await ai.removeOrphans() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These blobs are not referenced by any model manifest, so Ollama can never use them. They are deleted permanently.")
        }
    }

    private var subtitle: String {
        let ai = store.ai
        if ai.runtimes.isEmpty { return "No local AI runtime is running right now" }
        return ai.runtimes.map(\.name).joined(separator: ", ") + (ai.loaded.isEmpty ? " running, nothing loaded" : " · \(ai.loaded.count) model\(ai.loaded.count == 1 ? "" : "s") in memory")
    }
}

private struct RuntimesCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let ai = store.ai
        Card {
            CardHeader(title: "Runtimes", subtitle: "Detected from running processes", symbol: "cpu", colors: Theme.ai)
            if ai.runtimes.isEmpty {
                EmptyHint(symbol: "brain", title: "Nothing running",
                          detail: "Ollama, LM Studio, llama.cpp, MLX, ComfyUI, Draw Things, Jan, GPT4All and container engines are detected automatically.")
            }
            VStack(spacing: 8) {
                ForEach(ai.runtimes) { runtime in
                    let rows = store.rows(grouped: false).filter { runtime.pids.contains($0.pids.first ?? -1) }
                    let cpu = rows.reduce(0) { $0 + $1.cpu }
                    let memory = rows.reduce(0) { $0 + $1.memory }
                    HStack(spacing: 12) {
                        IconBadge(symbol: symbol(for: runtime.kind), colors: Theme.ai, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(runtime.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("\(runtime.pids.count) process\(runtime.pids.count == 1 ? "" : "es")\(runtime.endpoint.map { " · \($0.host ?? ""):\($0.port ?? 0)" } ?? "")")
                                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        if rows.first?.hasMetrics == true {
                            Text(String(format: "%.0f%% CPU", cpu)).font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.secondary)
                            Text(Fmt.memory(memory)).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !ai.runtimes.isEmpty {
                Divider().overlay(Theme.hairline).padding(.vertical, 12)
                HStack(alignment: .top) {
                    StatTile(label: "GPU now", value: Fmt.percent(store.gpu.device), caption: "device utilization")
                    StatTile(label: "GPU memory", value: Fmt.memory(store.gpu.inUseMemory), caption: "held by the driver")
                    if let w = store.sensors.systemPower { StatTile(label: "Power", value: Fmt.watts(w), caption: "whole system") }
                    if let t = store.sensors.average(.gpu) { StatTile(label: "GPU temp", value: store.settings.temperature(t), tint: Theme.thermal(t)) }
                }
            }
        }
    }

    private func symbol(for kind: AIRuntime.Kind) -> String {
        switch kind {
        case .ollama, .lmStudio, .llamaCpp, .mlx, .jan, .gpt4all, .msty: "text.bubble"
        case .comfyUI, .drawThings, .diffusionBee: "photo.artframe"
        case .openWebUI: "globe"
        case .orbStack, .docker, .colima: "shippingbox"
        case .pythonML: "chevron.left.forwardslash.chevron.right"
        }
    }
}

private struct HeadroomCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        Card {
            CardHeader(title: "Room for a Model", subtitle: "Estimate for 4-bit weights plus a 1 GB context allowance", symbol: "memorychip", colors: Theme.ai)
            if let h = store.ai.headroom {
                HStack(alignment: .top) {
                    StatTile(label: "Available now", value: Fmt.memory(h.availableNow), caption: "unified memory not in use")
                    StatTile(label: "GPU limit", value: Fmt.memory(h.workingSetLimit), caption: "Metal working set")
                    StatTile(label: "If you quit apps", value: "+" + Fmt.memory(h.reclaimable), caption: "about half of app memory")
                }
                .padding(.bottom, 12)
                VStack(spacing: 6) {
                    ForEach(h.rows) { row in
                        HStack(spacing: 10) {
                            Image(systemName: row.fits ? "checkmark.circle.fill" : (row.fitsAfterFreeing ? "minus.circle.fill" : "xmark.circle"))
                                .foregroundStyle(row.fits ? Theme.good : (row.fitsAfterFreeing ? Theme.warn : Theme.tertiary))
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(row.label) parameters").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("~\(Fmt.memory(row.bytes))").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                            Text(row.fits ? "Fits" : (row.fitsAfterFreeing ? "After quitting apps" : "Too big"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(row.fits ? Theme.good : (row.fitsAfterFreeing ? Theme.warn : Theme.tertiary))
                                .frame(width: 120, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Larger quantizations, long contexts and vision models need more; models can also spill into swap and still run slowly.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).padding(.top, 10)
            }
        }
    }
}

private struct LoadedModelsCard: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let ai = store.ai
        Card {
            CardHeader(title: "Loaded in Memory", subtitle: "\(Fmt.memory(ai.loadedBytes)) across \(ai.loaded.count) model\(ai.loaded.count == 1 ? "" : "s")",
                       symbol: "memorychip.fill", colors: Theme.ai) {
                if let message = ai.message { Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.secondary) }
            }
            VStack(spacing: 0) {
                ForEach(ai.loaded) { model in
                    HoverRow(accent: Theme.ai[1]) { hovering in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                                Text([model.runtime.rawValue, model.family, model.parameters, model.quantization,
                                      model.contextLength.map { "\($0.formatted()) ctx" },
                                      model.expiresAt.map { "unloads \($0.formatted(.relative(presentation: .named)))" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            if model.size > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Fmt.memory(model.size)).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                                    if let gpu = model.gpuSize, model.size > 0 {
                                        Text("\(Fmt.percent(Double(gpu) / Double(model.size))) on GPU").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                    }
                                }
                            }
                            if model.runtime == .ollama {
                                Button("Unload") { Task { await ai.unload(model) } }
                                    .buttonStyle(GhostButtonStyle(compact: true))
                                    .opacity(hovering ? 1 : 0.6)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, -16)
        }
    }
}

private struct ModelLibraryCard: View {
    @Environment(MonitorStore.self) private var store
    @Binding var confirmingOrphans: Bool

    var body: some View {
        let ai = store.ai
        Card {
            CardHeader(title: "Model Libraries on Disk", subtitle: ai.storesScannedAt.map { "\(Fmt.storage(ai.totalOnDisk)) · measured \($0.formatted(.relative(presentation: .named)))" } ?? "Not measured yet",
                       symbol: "internaldrive", colors: Theme.ai) {
                HStack(spacing: 8) {
                    if ai.scanningStores { ProgressView().controlSize(.small) }
                    Button { Task { await ai.scanStores() } } label: { Label("Measure", systemImage: "arrow.clockwise") }
                        .buttonStyle(GhostButtonStyle(compact: true)).disabled(ai.scanningStores)
                }
            }
            if ai.stores.isEmpty, !ai.scanningStores {
                EmptyHint(symbol: "folder", title: "No model libraries found",
                          detail: "Looks in ~/.ollama/models, ~/.lmstudio/models and the Hugging Face cache (~/.cache/huggingface/hub).")
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ai.stores) { summary in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(summary.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(abbreviated(summary.url.path)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            Spacer()
                            Text(Fmt.storage(summary.totalSize)).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                            IconButton(symbol: "folder", help: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([summary.url]) }
                        }
                        ForEach(summary.models.prefix(12)) { model in
                            HStack {
                                Text(model.name).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Spacer()
                                if let modified = model.modified {
                                    Text(modified.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                }
                                Text(Fmt.storage(model.size)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary).frame(width: 70, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if summary.models.count > 12 {
                            Text("and \(summary.models.count - 12) more").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }
            if !ai.orphans.isEmpty {
                Notice(symbol: "trash", color: Theme.warn,
                       text: "\(ai.orphans.count) orphaned Ollama blob\(ai.orphans.count == 1 ? "" : "s") (\(Fmt.storage(ai.orphanBytes))) belong to no model: leftovers of interrupted pulls or removed models.") {
                    Button("Delete") { confirmingOrphans = true }.buttonStyle(GhostButtonStyle(compact: true))
                }
                .padding(.top, 14)
            }
        }
    }
}
