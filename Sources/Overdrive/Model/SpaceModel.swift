import AppKit
import Observation
import OverdriveCore

/// Folder-size exploration for the Storage page's treemap.
@MainActor @Observable
final class SpaceModel {
    enum Phase { case idle, scanning, done }

    var phase: Phase = .idle
    var root: SpaceNode?
    var current: SpaceNode?
    var hovered: SpaceNode?
    var scanned = 0
    var bytesSoFar: UInt64 = 0
    var message: String?
    var rootURL: URL = Paths.home

    @ObservationIgnored private var scanner: SpaceScanner?

    func scan(_ url: URL? = nil) {
        scanner?.cancel()
        let target = url ?? Paths.home
        let scanner = SpaceScanner(root: target)
        self.scanner = scanner
        rootURL = target
        phase = .scanning
        scanned = 0
        bytesSoFar = 0
        root = nil
        current = nil
        hovered = nil
        message = nil
        Task {
            let tree = await Task.detached {
                scanner.scan { count, bytes in
                    DispatchQueue.main.async { self.scanned = count; self.bytesSoFar = bytes }
                }
            }.value
            guard self.scanner === scanner else { return }
            root = tree
            current = tree
            phase = .done
        }
    }

    func cancel() { scanner?.cancel() }

    func open(_ node: SpaceNode) {
        guard node.isDirectory, !node.isPackage, !node.isSummary else { return }
        current = node
        hovered = nil
    }

    func up() {
        if let parent = current?.parent { current = parent }
    }

    func reveal(_ node: SpaceNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func trash(_ node: SpaceNode) {
        guard !node.isSummary, let parent = node.parent else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            parent.remove(child: node)
            message = "Moved \(node.name) (\(Fmt.storage(node.size))) to the Trash."
            // Re-point the view so SwiftUI redraws from the mutated tree.
            let keep = current
            current = nil
            current = keep
            MonitorStore.shared.refreshVolumes()
        } catch {
            message = (error as NSError).localizedDescription
        }
    }

    /// Lets the person pick any folder (and, in the sandbox, grants access to it for this session).
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder to map."
        panel.directoryURL = rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        scan(url)
    }
}
