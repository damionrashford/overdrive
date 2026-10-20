import CoreServices
import Foundation

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let isSystem: Bool
    public var size: UInt64?
    public var lastUsed: Date?

    public init(url: URL, name: String, bundleID: String?, version: String?, isSystem: Bool, size: UInt64?, lastUsed: Date?) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.isSystem = isSystem
        self.size = size
        self.lastUsed = lastUsed
    }
}

public struct LeftoverItem: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable { case support = "Application Support", cache = "Cache", preferences = "Preferences",
                                         container = "Container", groupContainer = "Group Container", logs = "Logs",
                                         savedState = "Saved State", webKit = "WebKit Data", cookies = "Cookies",
                                         launchAgent = "Launch Agent", scripts = "Application Scripts", other = "Other" }
    public var id: String { url.path }
    public let url: URL
    public let kind: Kind
    public let size: UInt64
    /// Items under /Library need an administrator to remove; they are listed but not selected.
    public let requiresAdmin: Bool
}

public enum AppInventory {
    public static let applicationFolders = ["/Applications", "/Applications/Utilities"]

    /// Apps in /Applications and ~/Applications, without sizes (measure lazily; it is slow).
    public static func list(home: URL = Paths.home) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        let folders = applicationFolders.map { URL(fileURLWithPath: $0, isDirectory: true) } + [home.appending(path: "Applications")]
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isPackageKey, .contentAccessDateKey],
                                                                      options: [.skipsHiddenFiles])) ?? []
            for url in items where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let info = bundle?.infoDictionary ?? [:]
                let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let id = bundle?.bundleIdentifier
                apps.append(InstalledApp(url: url, name: name, bundleID: id,
                                         version: info["CFBundleShortVersionString"] as? String,
                                         isSystem: id?.hasPrefix("com.apple.") == true, size: nil, lastUsed: lastUsed(url)))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Spotlight's last-used date, the one Finder and Launchpad show. Nil when Spotlight has not indexed the app.
    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
              let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date, date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }

    /// Files an app leaves behind in Library folders, matched by bundle identifier and, for
    /// folders named after the app, by name.
    public static func leftovers(for app: InstalledApp, home: URL = Paths.home) -> [LeftoverItem] {
        var found: [LeftoverItem] = []
        let id = app.bundleID?.lowercased()
        let name = app.name.lowercased()
        let fm = FileManager.default

        func matches(_ fileName: String, byName: Bool) -> Bool {
            let lower = fileName.lowercased()
            if let id, !id.isEmpty, lower == id || lower.hasPrefix(id + ".") || lower.hasPrefix(id + "-") || lower.contains(id + ".") {
                return true
            }
            // Group containers are "TEAMID.bundle.id".
            if let id, lower.hasSuffix("." + id) { return true }
            return byName && lower == name
        }

        func scan(_ folder: URL, kind: LeftoverItem.Kind, byName: Bool, admin: Bool = false) {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: []) else { return }
            for url in items where matches(url.lastPathComponent, byName: byName) {
                found.append(LeftoverItem(url: url, kind: kind, size: DirectorySize.of(url), requiresAdmin: admin))
            }
        }

        let lib = home.appending(path: "Library")
        scan(lib.appending(path: "Application Support"), kind: .support, byName: true)
        scan(lib.appending(path: "Caches"), kind: .cache, byName: true)
        scan(lib.appending(path: "Preferences"), kind: .preferences, byName: false)
        scan(lib.appending(path: "Containers"), kind: .container, byName: false)
        scan(lib.appending(path: "Group Containers"), kind: .groupContainer, byName: false)
        scan(lib.appending(path: "Logs"), kind: .logs, byName: true)
        scan(lib.appending(path: "Saved Application State"), kind: .savedState, byName: false)
        scan(lib.appending(path: "WebKit"), kind: .webKit, byName: false)
        scan(lib.appending(path: "HTTPStorages"), kind: .webKit, byName: false)
        scan(lib.appending(path: "Cookies"), kind: .cookies, byName: false)
        scan(lib.appending(path: "LaunchAgents"), kind: .launchAgent, byName: false)
        scan(lib.appending(path: "Application Scripts"), kind: .scripts, byName: false)
        let system = URL(fileURLWithPath: "/Library", isDirectory: true)
        scan(system.appending(path: "Application Support"), kind: .support, byName: true, admin: true)
        scan(system.appending(path: "LaunchAgents"), kind: .launchAgent, byName: false, admin: true)
        scan(system.appending(path: "LaunchDaemons"), kind: .launchAgent, byName: false, admin: true)
        scan(system.appending(path: "Preferences"), kind: .preferences, byName: false, admin: true)
        return found.sorted { $0.size > $1.size }
    }

    public struct UninstallOutcome: Sendable {
        public var trashed: [URL] = []
        public var failures: [String] = []
        public var bytes: UInt64 = 0
    }

    /// Moves the app and the chosen leftovers to the Trash. Nothing is deleted outright.
    public static func uninstall(_ app: InstalledApp, leftovers: [LeftoverItem], includeApp: Bool) -> UninstallOutcome {
        var outcome = UninstallOutcome()
        let fm = FileManager.default
        var targets: [(URL, UInt64)] = leftovers.map { ($0.url, $0.size) }
        if includeApp { targets.insert((app.url, app.size ?? 0), at: 0) }
        for (url, size) in targets {
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                outcome.trashed.append(url)
                outcome.bytes += size
            } catch {
                outcome.failures.append("\(url.lastPathComponent): \((error as NSError).localizedDescription)")
            }
        }
        return outcome
    }
}
