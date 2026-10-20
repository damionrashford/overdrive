import Foundation

/// A launchd job definition on disk: user agents, system agents and daemons.
public struct StartupItem: Sendable, Identifiable, Hashable {
    public enum Scope: String, Sendable { case userAgent = "Your login", globalAgent = "All users", daemon = "System daemon" }

    public var id: String { url.path }
    public let url: URL
    public let label: String
    public let program: String
    public let scope: Scope
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let interval: Int?
    public let modified: Date?
    /// Set by the direct edition from `launchctl print-disabled`; nil when unknown.
    public var disabled: Bool?

    public var isApple: Bool { label.hasPrefix("com.apple.") }
    public var vendor: String {
        let parts = label.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : label
    }
}

public enum StartupItems {
    public static func list(home: URL = Paths.home) -> [StartupItem] {
        var items: [StartupItem] = []
        let sources: [(URL, StartupItem.Scope)] = [
            (home.appending(path: "Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        for (folder, scope) in sources {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                      options: [.skipsHiddenFiles])) ?? []
            for url in files where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                var program = plist["Program"] as? String ?? ""
                if program.isEmpty, let args = plist["ProgramArguments"] as? [String] { program = args.joined(separator: " ") }
                let keepAlive: Bool
                if let b = plist["KeepAlive"] as? Bool { keepAlive = b } else { keepAlive = plist["KeepAlive"] is [String: Any] }
                items.append(StartupItem(
                    url: url, label: label, program: program, scope: scope,
                    runAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive,
                    interval: plist["StartInterval"] as? Int,
                    modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                    disabled: nil))
            }
        }
        return items.sorted { ($0.isApple ? 1 : 0, $0.label) < ($1.isApple ? 1 : 0, $1.label) }
    }

    /// Parses `launchctl print-disabled` output: lines like `"com.foo.agent" => disabled`.
    public static func parseDisabled(_ output: String) -> Set<String> {
        var disabled: Set<String> = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasSuffix("=> disabled") || text.hasSuffix("=> true"),
                  let open = text.firstIndex(of: "\""), let close = text[text.index(after: open)...].firstIndex(of: "\"") else { continue }
            disabled.insert(String(text[text.index(after: open)..<close]))
        }
        return disabled
    }
}
