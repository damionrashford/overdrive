import Foundation

public enum RemovalMode: Sendable, Hashable {
    /// Delete the item itself (a cache folder an app recreates).
    case removeItem
    /// Empty the folder but keep it (DerivedData, Trash).
    case removeContents
    /// Move to the Trash: used for anything that was the person's own file.
    case trash
}

public struct CleanupItem: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let title: String
    public let url: URL
    public let mode: RemovalMode
    public let defaultSelected: Bool
    public let note: String?

    public init(title: String, url: URL, mode: RemovalMode, defaultSelected: Bool, note: String? = nil) {
        self.title = title
        self.url = url
        self.mode = mode
        self.defaultSelected = defaultSelected
        self.note = note
    }
}

public struct CleanupCategory: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let items: [CleanupItem]
}

public enum CleanupCatalog {
    /// Caches that are expensive to rebuild, so they are listed but not preselected.
    static let keepByDefault: Set<String> = ["ms-playwright", "puppeteer", "Cypress", "JetBrains", "pypoetry", "huggingface"]

    public static func build(home: URL = Paths.home,
                             ownBundleID: String? = Bundle.main.bundleIdentifier,
                             now: Date = Date()) -> [CleanupCategory] {
        var categories: [CleanupCategory] = []

        let caches = children(of: home.appending(path: "Library/Caches")).compactMap { url -> CleanupItem? in
            let name = url.lastPathComponent
            if name == ownBundleID { return nil }
            let isApple = name.hasPrefix("com.apple.")
            return CleanupItem(
                title: name, url: url, mode: .removeItem,
                defaultSelected: !isApple && !keepByDefault.contains(name),
                note: isApple ? "macOS system cache" : (keepByDefault.contains(name) ? "Slow to re-download" : nil)
            )
        }
        if !caches.isEmpty {
            categories.append(CleanupCategory(id: "caches", title: "App Caches",
                                              subtitle: "Temporary data apps rebuild on demand", symbol: "shippingbox", items: caches))
        }

        let logs = children(of: home.appending(path: "Library/Logs")).map {
            CleanupItem(title: $0.lastPathComponent, url: $0, mode: .removeItem, defaultSelected: true)
        }
        if !logs.isEmpty {
            categories.append(CleanupCategory(id: "logs", title: "Logs & Crash Reports",
                                              subtitle: "Diagnostic files nobody reads", symbol: "doc.text.magnifyingglass", items: logs))
        }

        let dev: [(String, String, Bool, String?)] = [
            ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData", true, "Rebuilt on next build"),
            ("Xcode Previews", "Library/Developer/Xcode/UserData/Previews", true, nil),
            ("iOS Device Support", "Library/Developer/Xcode/iOS DeviceSupport", true, "Re-fetched when a device connects"),
            ("watchOS Device Support", "Library/Developer/Xcode/watchOS DeviceSupport", true, "Re-fetched when a device connects"),
            ("Simulator Caches", "Library/Developer/CoreSimulator/Caches", true, nil),
            ("Xcode Archives", "Library/Developer/Xcode/Archives", false, "Needed to symbolicate shipped builds"),
            ("npm Cache", ".npm/_cacache", true, nil),
            ("Bun Cache", ".bun/install/cache", true, nil),
            ("Yarn Cache", ".yarn/berry/cache", true, nil),
            ("pnpm Store", "Library/pnpm/store", false, "Shared by linked node_modules"),
            ("pip Cache", ".cache/pip", true, nil),
            ("uv Cache", ".cache/uv", true, nil),
            ("Hugging Face Models", ".cache/huggingface", false, "Downloaded models"),
            ("Cargo Registry Cache", ".cargo/registry/cache", true, nil),
            ("Gradle Caches", ".gradle/caches", true, nil),
            ("Maven Repository", ".m2/repository", false, "Re-downloaded on next build"),
        ]
        let devItems = dev.compactMap { title, path, selected, note -> CleanupItem? in
            let url = home.appending(path: path)
            guard isDirectory(url) else { return nil }
            return CleanupItem(title: title, url: url, mode: .removeContents, defaultSelected: selected, note: note)
        }
        if !devItems.isEmpty {
            categories.append(CleanupCategory(id: "developer", title: "Developer Junk",
                                              subtitle: "Build products and package caches", symbol: "hammer", items: devItems))
        }

        let trash = home.appending(path: ".Trash")
        if isDirectory(trash) {
            categories.append(CleanupCategory(id: "trash", title: "Trash", subtitle: "Files already thrown away", symbol: "trash",
                                              items: [CleanupItem(title: "Trash", url: trash, mode: .removeContents, defaultSelected: true,
                                                                  note: "Permanently deleted")]))
        }

        let cutoff = now.addingTimeInterval(-90 * 86_400)
        let installers: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
        let downloads = children(of: home.appending(path: "Downloads")).compactMap { url -> CleanupItem? in
            let ext = url.pathExtension.lowercased()
            let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
            let added = values?.addedToDirectoryDate ?? values?.creationDate ?? now
            if installers.contains(ext) {
                return CleanupItem(title: url.lastPathComponent, url: url, mode: .trash, defaultSelected: false, note: "Installer")
            }
            guard added < cutoff else { return nil }
            return CleanupItem(title: url.lastPathComponent, url: url, mode: .trash, defaultSelected: false,
                               note: "Added \(added.formatted(.relative(presentation: .named)))")
        }
        if !downloads.isEmpty {
            categories.append(CleanupCategory(id: "downloads", title: "Old Downloads",
                                              subtitle: "Installers and files untouched for 90+ days, moved to Trash",
                                              symbol: "arrow.down.circle", items: downloads))
        }
        return categories
    }

    static func children(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        return items.filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

public enum DirectorySize {
    /// On-disk allocated size, without following symlinks out of the tree.
    public static func of(_ url: URL, isCancelled: () -> Bool = { false }) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let top = try? url.resourceValues(forKeys: keys.union([.isDirectoryKey])) else { return 0 }
        if top.isSymbolicLink == true { return 0 }
        if top.isDirectory != true { return UInt64(top.totalFileAllocatedSize ?? 0) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                                              errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        var n = 0
        for case let file as URL in enumerator {
            n += 1
            if n % 4096 == 0, isCancelled() { break }
            guard let v = try? file.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

public struct CleanupOutcome: Sendable {
    public var removed = 0
    public var failures: [String] = []
    public init() {}
}

public enum CleanupEngine {
    /// Folders that must never be removed or emptied wholesale, whatever the catalog says.
    static let protectedRelative = ["", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music",
                                    "Applications", "Library", "Library/Mobile Documents", "Library/CloudStorage"]

    public static func isSafeTarget(_ url: URL, mode: RemovalMode, home: URL) -> Bool {
        let homePath = home.standardizedFileURL.resolvingSymlinksInPath().path
        // Emptying a folder follows it, so a symlinked cache dir must not lead outside the home folder.
        let checked = mode == .removeContents ? url.standardizedFileURL.resolvingSymlinksInPath()
                                              : url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
                                                  .appending(path: url.lastPathComponent)
        let path = checked.path
        guard path.hasPrefix(homePath + "/") else { return false }
        let relative = String(path.dropFirst(homePath.count + 1))
        if relative.split(separator: "/").contains("..") { return false }
        return !protectedRelative.contains(relative)
    }

    public static func clean(_ item: CleanupItem, home: URL = Paths.home) -> CleanupOutcome {
        var outcome = CleanupOutcome()
        guard isSafeTarget(item.url, mode: item.mode, home: home) else {
            outcome.failures.append("\(item.title): refused, outside the safe area")
            return outcome
        }
        let fm = FileManager.default
        func attempt(_ url: URL, _ body: () throws -> Void) {
            do {
                try body()
                outcome.removed += 1
            } catch {
                outcome.failures.append("\(url.lastPathComponent): \((error as NSError).localizedDescription)")
            }
        }
        switch item.mode {
        case .removeItem:
            attempt(item.url) { try fm.removeItem(at: item.url) }
        case .trash:
            attempt(item.url) { try fm.trashItem(at: item.url, resultingItemURL: nil) }
        case .removeContents:
            let children = (try? fm.contentsOfDirectory(at: item.url, includingPropertiesForKeys: nil, options: [])) ?? []
            for child in children { attempt(child) { try fm.removeItem(at: child) } }
        }
        return outcome
    }
}
