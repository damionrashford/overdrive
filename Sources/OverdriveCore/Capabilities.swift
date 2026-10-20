import Darwin
import Foundation

/// What this build of Overdrive may do on this Mac. The App Store edition runs in the App Sandbox,
/// which blocks signalling or terminating other processes, per-process energy accounting, the SMC
/// user client and administrator commands; the direct edition has all of them.
public struct Capabilities: Sendable {
    public let isSandboxed: Bool
    /// Quit / force-quit other apps and processes.
    public let canQuitProcesses: Bool
    /// Per-process disk I/O (`proc_pid_rusage` on other processes).
    public let hasProcessDiskIO: Bool
    public let canRunShell: Bool
    public let canReadSensors: Bool
    /// The person's real home folder, even inside a sandbox container.
    public let realHome: URL

    public static let current: Capabilities = {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let home: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        return Capabilities(
            isSandboxed: sandboxed,
            canQuitProcesses: !sandboxed,
            hasProcessDiskIO: !sandboxed,
            canRunShell: !sandboxed,
            canReadSensors: !sandboxed && SMCReader.isAvailable,
            realHome: home
        )
    }()

    public var editionName: String { isSandboxed ? "App Store edition" : "Direct edition" }
}
