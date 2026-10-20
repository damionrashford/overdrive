import AppKit
import Observation
import OverdriveCore

/// In the App Sandbox, cleanup and scans can only touch folders the person has granted. The grant is
/// remembered as a security-scoped bookmark so it survives relaunches.
@MainActor @Observable
final class AccessManager {
    private static let bookmarkKey = "homeFolderBookmark"

    let isRequired = Capabilities.current.isSandboxed
    private(set) var grantedURL: URL?
    private(set) var lastError: String?

    var hasAccess: Bool { !isRequired || grantedURL != nil }

    init() {
        restore()
    }

    private func restore() {
        guard isRequired, let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        apply(url)
        if stale { save(url) }
    }

    /// Shows the open panel on the real home folder. Any folder works; the home folder enables everything.
    func requestAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = Capabilities.current.realHome
        panel.prompt = "Grant Access"
        panel.message = "Choose your home folder so Overdrive can measure caches, logs and large files. Nothing is removed without your confirmation."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "macOS did not allow access to that folder."
            return
        }
        save(url)
        apply(url)
    }

    func revoke() {
        grantedURL?.stopAccessingSecurityScopedResource()
        grantedURL = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        Paths.home = Capabilities.current.realHome
    }

    private func save(_ url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ url: URL) {
        grantedURL = url
        if !Paths.isOverridden { Paths.home = url }
    }
}
