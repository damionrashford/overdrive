import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let output: String
    public var cancelled: Bool { status != 0 && output.contains("-128") }
    public var succeeded: Bool { status == 0 }

    /// The most useful single line to show a person: the last non-empty line of output.
    public var summary: String {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
    }
}

public enum Shell {
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        return env
    }()

    public static func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = environment
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, output: error.localizedDescription))
                    return
                }
                // Drain before waiting so a chatty command cannot fill the pipe and stall.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: ShellResult(status: process.terminationStatus,
                                                           output: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    public static func sh(_ command: String) async -> ShellResult {
        await run("/bin/sh", ["-c", command])
    }

    /// Runs a command as root through the standard macOS authorization dialog.
    public static func runAsAdmin(_ command: String, prompt: String) async -> ShellResult {
        await run("/usr/bin/osascript", ["-e", adminScript(command, prompt: prompt)])
    }

    static func adminScript(_ command: String, prompt: String) -> String {
        "do shell script \"\(appleScriptEscape(command))\" with prompt \"\(appleScriptEscape(prompt))\" with administrator privileges"
    }

    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public enum MaintenanceEffect: Sendable {
    case none, memory, disk
}

public struct MaintenanceTask: Sendable, Identifiable {
    public enum Runner: Sendable {
        case shell(String)
        case admin(String)
        case appleScript(String)
    }

    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let runner: Runner
    public let caution: String?
    public let effect: MaintenanceEffect
    public let successMessage: String

    public var requiresAdmin: Bool {
        if case .admin = runner { return true }
        return false
    }

    public func run() async -> ShellResult {
        switch runner {
        case .shell(let command):
            return await Shell.sh(command)
        case .admin(let command):
            return await Shell.runAsAdmin(command, prompt: "Overdrive needs your password to \(title.lowercased()).")
        case .appleScript(let script):
            return await Shell.run("/usr/bin/osascript", ["-e", script])
        }
    }
}

public enum MaintenanceCatalog {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public static func all(fileManager fm: FileManager = .default) -> [MaintenanceTask] {
        var tasks: [MaintenanceTask] = [
            MaintenanceTask(id: "purge", title: "Free Up Memory",
                            detail: "Flushes inactive file cache so apps get free RAM immediately.",
                            symbol: "memorychip", runner: .admin("/usr/sbin/purge"), caution: nil,
                            effect: .memory, successMessage: "Inactive memory released"),
            MaintenanceTask(id: "snapshots", title: "Reclaim Purgeable Space",
                            detail: "Thins local Time Machine snapshots that hold deleted files on disk.",
                            symbol: "externaldrive.badge.timemachine",
                            runner: .admin("/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"), caution: nil,
                            effect: .disk, successMessage: "Local snapshots thinned"),
            MaintenanceTask(id: "trash", title: "Empty Trash",
                            detail: "Permanently deletes everything in the Trash on every volume.",
                            symbol: "trash", runner: .appleScript("tell application \"Finder\" to empty trash"),
                            caution: "Cannot be undone", effect: .disk, successMessage: "Trash emptied"),
            MaintenanceTask(id: "dns", title: "Flush DNS Cache",
                            detail: "Fixes sites that won't load after DNS or VPN changes.",
                            symbol: "network",
                            runner: .admin("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"),
                            caution: nil, effect: .none, successMessage: "DNS cache flushed"),
            MaintenanceTask(id: "quicklook", title: "Reset Quick Look",
                            detail: "Clears thumbnail and preview caches when previews look wrong.",
                            symbol: "eye", runner: .shell("/usr/bin/qlmanage -r cache && /usr/bin/qlmanage -r"),
                            caution: nil, effect: .disk, successMessage: "Quick Look caches reset"),
            MaintenanceTask(id: "launchservices", title: "Repair “Open With”",
                            detail: "Rebuilds the Launch Services database: fixes duplicate apps and wrong default apps.",
                            symbol: "square.stack.3d.up", runner: .shell("\(lsregister) -gc -r -f -apps u,s,l"),
                            caution: "Takes up to a minute", effect: .none, successMessage: "App registrations rebuilt"),
            MaintenanceTask(id: "relaunch", title: "Restart Dock & Finder",
                            detail: "Clears stuck menus, frozen Dock icons and Finder glitches.",
                            symbol: "dock.rectangle", runner: .shell("/usr/bin/killall Dock; /usr/bin/killall Finder; exit 0"),
                            caution: nil, effect: .none, successMessage: "Dock and Finder restarted"),
            MaintenanceTask(id: "spotlight", title: "Rebuild Spotlight Index",
                            detail: "Re-indexes the startup disk when search misses files or mds hogs CPU.",
                            symbol: "magnifyingglass", runner: .admin("/usr/bin/mdutil -E /"),
                            caution: "Search is incomplete while re-indexing", effect: .none,
                            successMessage: "Re-indexing started"),
        ]
        if fm.fileExists(atPath: "/Applications/Xcode.app") {
            tasks.append(MaintenanceTask(id: "simulators", title: "Delete Old Simulators",
                                         detail: "Removes simulators for iOS versions Xcode no longer supports.",
                                         symbol: "iphone.gen3", runner: .shell("/usr/bin/xcrun simctl delete unavailable"),
                                         caution: nil, effect: .disk, successMessage: "Unavailable simulators deleted"))
        }
        if let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { fm.isExecutableFile(atPath: $0) }) {
            tasks.append(MaintenanceTask(id: "brew", title: "Homebrew Cleanup",
                                         detail: "Removes old formula versions and Homebrew's download cache.",
                                         symbol: "mug", runner: .shell("\(brew) cleanup --prune=all 2>&1"),
                                         caution: nil, effect: .disk, successMessage: "Homebrew cleaned"))
        }
        return tasks
    }
}
