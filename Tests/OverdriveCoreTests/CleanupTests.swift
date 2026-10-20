import Foundation
import Testing
@testable import OverdriveCore

/// Every test builds a throwaway home folder; nothing here touches the real one.
@Suite struct CleanupTests {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "overdrive-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func write(_ relative: String, bytes: Int = 8192) throws {
        let url = home.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appending(path: relative).path)
    }

    @Test func catalogFindsJunkAndPreselectsSafely() throws {
        try write("Library/Caches/com.example.app/blob")
        try write("Library/Caches/com.apple.Safari/blob")
        try write("Library/Caches/ms-playwright/chromium")
        try write("Library/Logs/thing.log")
        try write("Library/Developer/Xcode/DerivedData/Proj-abc/Build/x.o")
        try write("Library/Developer/Xcode/Archives/2026/a.xcarchive/Info.plist")
        try write(".npm/_cacache/index")
        try write("Downloads/Installer.dmg")
        try write("Downloads/recent.txt")

        let categories = CleanupCatalog.build(home: home, ownBundleID: "com.overdrive.test")
        let items = Dictionary(uniqueKeysWithValues: categories.flatMap(\.items).map { ($0.title, $0) })

        #expect(items["com.example.app"]?.defaultSelected == true)
        #expect(items["com.apple.Safari"]?.defaultSelected == false)
        #expect(items["ms-playwright"]?.defaultSelected == false)
        #expect(items["thing.log"]?.defaultSelected == true)
        #expect(items["Xcode DerivedData"]?.mode == .removeContents)
        #expect(items["Xcode Archives"]?.defaultSelected == false)
        #expect(items["npm Cache"] != nil)
        #expect(items["Installer.dmg"]?.mode == .trash)
        #expect(items["Installer.dmg"]?.defaultSelected == false)
        #expect(items["recent.txt"] == nil, "recent downloads are not junk")
    }

    @Test func sizesAreMeasured() throws {
        try write("Library/Caches/big/a", bytes: 1_000_000)
        try write("Library/Caches/big/nested/b", bytes: 500_000)
        let size = DirectorySize.of(home.appending(path: "Library/Caches/big"))
        #expect(size >= 1_500_000)
    }

    @Test func removeContentsKeepsTheFolder() throws {
        try write("Library/Developer/Xcode/DerivedData/Proj/Build/x.o")
        try write("Library/Developer/Xcode/DerivedData/Other/y.o")
        let item = CleanupItem(title: "DD", url: home.appending(path: "Library/Developer/Xcode/DerivedData"),
                               mode: .removeContents, defaultSelected: true)
        let outcome = CleanupEngine.clean(item, home: home)
        #expect(outcome.failures.isEmpty)
        #expect(outcome.removed == 2)
        #expect(exists("Library/Developer/Xcode/DerivedData"))
        #expect(!exists("Library/Developer/Xcode/DerivedData/Proj"))
    }

    @Test func removeItemDeletesTheCache() throws {
        try write("Library/Caches/com.example.app/blob")
        let item = CleanupItem(title: "c", url: home.appending(path: "Library/Caches/com.example.app"),
                               mode: .removeItem, defaultSelected: true)
        #expect(CleanupEngine.clean(item, home: home).failures.isEmpty)
        #expect(!exists("Library/Caches/com.example.app"))
        #expect(exists("Library/Caches"))
    }

    @Test func refusesProtectedAndOutsidePaths() throws {
        for relative in ["", "Documents", "Library", "Desktop", "Downloads"] {
            let url = relative.isEmpty ? home : home.appending(path: relative)
            #expect(!CleanupEngine.isSafeTarget(url, mode: .removeContents, home: home), "\(relative)")
            #expect(!CleanupEngine.isSafeTarget(url, mode: .removeItem, home: home), "\(relative)")
        }
        #expect(!CleanupEngine.isSafeTarget(URL(fileURLWithPath: "/usr/local"), mode: .removeItem, home: home))
        #expect(!CleanupEngine.isSafeTarget(home.appending(path: "Library/../../etc"), mode: .removeItem, home: home))
        #expect(CleanupEngine.isSafeTarget(home.appending(path: "Library/Caches/x"), mode: .removeItem, home: home))
    }

    @Test func refusesToEmptyASymlinkLeadingOutsideHome() throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "overdrive-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data([1]).write(to: outside.appending(path: "precious"))
        try FileManager.default.createDirectory(at: home.appending(path: "Library/Caches"), withIntermediateDirectories: true)
        let link = home.appending(path: "Library/Caches/evil")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let empty = CleanupItem(title: "evil", url: link, mode: .removeContents, defaultSelected: true)
        #expect(!CleanupEngine.clean(empty, home: home).failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "precious").path))

        // Deleting the link itself is fine and leaves the target alone.
        let remove = CleanupItem(title: "evil", url: link, mode: .removeItem, defaultSelected: true)
        #expect(CleanupEngine.clean(remove, home: home).failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: outside.appending(path: "precious").path))
    }

    @Test func largeFileScanFindsBigFilesAndSkipsExcluded() throws {
        try write("Movies/big.mov", bytes: 3_000_000)
        try write("Movies/small.mov", bytes: 10_000)
        try write("Library/huge.bin", bytes: 3_000_000)
        try write("Code/node_modules/dep/huge.bin", bytes: 3_000_000)
        let scanner = LargeFileScanner(root: home, minimumSize: 2_000_000, excluded: [home.appending(path: "Library")])
        var progressCalls = 0
        let found = scanner.scan { _ in progressCalls += 1 }
        #expect(found.map(\.url.lastPathComponent) == ["big.mov"])
        #expect(progressCalls > 0)
    }

    @Test func adminScriptEscapesQuotes() {
        let script = Shell.adminScript("echo \"hi\" \\ there", prompt: "Need \"it\"")
        #expect(script == #"do shell script "echo \"hi\" \\ there" with prompt "Need \"it\"" with administrator privileges"#)
    }

    @Test func shellRunsAndCapturesOutput() async {
        let ok = await Shell.sh("echo hello; echo second >&2")
        #expect(ok.succeeded)
        #expect(ok.output.contains("hello") && ok.output.contains("second"))
        #expect(ok.summary == "second")
        let fail = await Shell.sh("exit 3")
        #expect(fail.status == 3)
        // A real AppleScript round trip, without administrator rights, proves the quoting reaches the shell intact.
        let echoed = await Shell.run("/usr/bin/osascript", ["-e", "do shell script \"\(Shell.appleScriptEscape("printf '%s' \"q\""))\""])
        #expect(echoed.output.trimmingCharacters(in: .whitespacesAndNewlines) == "q")
    }

    @Test func cancelledPasswordDialogIsRecognized() {
        // What osascript prints when the person clicks Cancel in the administrator dialog.
        let cancelled = ShellResult(status: 1, output: "0:58: execution error: User canceled. (-128)\n")
        #expect(cancelled.cancelled && !cancelled.succeeded)
        let failed = ShellResult(status: 1, output: "purge: Operation not permitted\n")
        #expect(!failed.cancelled)
        #expect(failed.summary == "purge: Operation not permitted")
    }

    @Test func maintenanceCommandsPointAtRealBinaries() {
        for task in MaintenanceCatalog.all() {
            let command: String
            switch task.runner {
            case .shell(let c), .admin(let c): command = c
            case .appleScript: continue
            }
            let binary = String(command.split(separator: " ").first ?? "")
            #expect(FileManager.default.isExecutableFile(atPath: binary), "\(task.id): \(binary)")
        }
    }
}
