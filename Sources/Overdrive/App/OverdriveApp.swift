import AppKit
import OverdriveCore
import SwiftUI

@main
struct OverdriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = MonitorStore.shared

    init() {
        if CommandLine.arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
        if CommandLine.arguments.contains("--dump-net") {
            Diagnostics.dumpNetwork()
            exit(0)
        }
    }

    var body: some Scene {
        Window("Overdrive", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 1120, minHeight: 740)
                .task { LaunchOptions.apply(to: store) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1300, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Overdrive") { AboutWindow.show(store: store) }
            }
            CommandGroup(after: .appInfo) {
                Button("Welcome to Overdrive") { WelcomeWindow.show(store: store) }
            }
            CommandMenu("Go") {
                ForEach(Array((Page.monitor + Page.optimize).enumerated()), id: \.element) { index, page in
                    if index < 9 {
                        Button(page.title) { store.page = page }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else {
                        Button(page.title) { store.page = page }
                    }
                }
            }
            CommandGroup(replacing: .help) {
                Button("Copy System Report") { Report.copy(store: store) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Save System Report…") { Report.save(store: store) }
                Divider()
                Link("Overdrive on GitHub", destination: Links.repository)
                Link("Privacy Policy", destination: Links.privacy)
                Link("Report a Problem", destination: Links.issues)
            }
        }

        Settings {
            SettingsView().environment(store)
        }

        MenuBarExtra {
            MenuBarPanel().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

enum Links {
    static let repository = URL(string: "https://github.com/damionrashford/overdrive")!
    static let privacy = URL(string: "https://github.com/damionrashford/overdrive/blob/main/docs/privacy-policy.md")!
    static let issues = URL(string: "https://github.com/damionrashford/overdrive/issues")!
    static let license = URL(string: "https://github.com/damionrashford/overdrive/blob/main/LICENSE")!
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let store = MonitorStore.shared
            store.start()
            let scripted = CommandLine.arguments.contains { $0.hasPrefix("--") }
            if !store.settings.hasSeenWelcome, !scripted {
                WelcomeWindow.show(store: store)
            }
        }
    }

    /// Closing the window leaves Overdrive running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

/// Hidden flags for screenshots and smoke tests: `--page cpu`, `--scan`, `--large-root <dir>`,
/// `--appearance light|dark`, `--window 1440x900`, `--show welcome|about|settings`, `--e2e`, `--render-menubar <png>`.
enum LaunchOptions {
    @MainActor static func apply(to store: MonitorStore) {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let raw = value(after: "--page"), let page = Page(rawValue: raw) { store.page = page }
        if let appearance = value(after: "--appearance") {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        if let size = value(after: "--window") {
            let parts = size.split(separator: "x").compactMap { Double($0) }
            // State restoration re-applies the saved frame shortly after launch; resize once it has settled.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard parts.count == 2, let window = NSApp.windows.first(where: { $0.title == "Overdrive" }) else { return }
                window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                window.center()
            }
        }
        switch value(after: "--show") {
        case "welcome": WelcomeWindow.show(store: store)
        case "about": AboutWindow.show(store: store)
        default: break
        }
        if args.contains("--scan") { Task { await store.cleanup.scan(exclusions: store.settings.cleanupExclusions) } }
        if let root = value(after: "--large-root") {
            if let mb = value(after: "--threshold-mb").flatMap(UInt64.init) { store.largeFiles.threshold = mb * 1_000_000 }
            store.largeFiles.scan(root: URL(fileURLWithPath: root))
        }
        if args.contains("--e2e") { Task { await SelfTest.run(store) } }
        if let out = value(after: "--render-menubar") {
            Task {
                try? await Task.sleep(for: .seconds(8))
                let renderer = ImageRenderer(content: MenuBarPanel().environment(store).background(Theme.background))
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                }
                exit(0)
            }
        }
    }
}

enum Report {
    @MainActor static func copy(store: MonitorStore) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.report(), forType: .string)
    }

    @MainActor static func save(store: MonitorStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Overdrive Report.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.report().write(to: url, atomically: true, encoding: .utf8)
    }
}
