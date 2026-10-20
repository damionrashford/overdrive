import AppKit
import OverdriveCore
import SwiftUI

/// Small auxiliary windows hosted in plain NSWindows so they can open from menu commands at any time.
@MainActor
enum AuxiliaryWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content().frame(width: size.width, height: size.height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[id] = window
    }

    static func close(id: String) {
        windows[id]?.close()
        windows[id] = nil
    }
}

enum WelcomeWindow {
    @MainActor static func show(store: MonitorStore) {
        AuxiliaryWindow.show(id: "welcome", title: "Welcome to Overdrive", size: NSSize(width: 560, height: 600)) {
            WelcomeView().environment(store)
        }
    }
}

enum AboutWindow {
    @MainActor static func show(store: MonitorStore) {
        AuxiliaryWindow.show(id: "about", title: "About Overdrive", size: NSSize(width: 420, height: 360)) {
            AboutView().environment(store)
        }
    }
}

private struct WelcomeView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                LogoMark(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overdrive").font(Theme.rounded(24, .bold)).foregroundStyle(Theme.text)
                    Text("See what your Mac is doing. Fix what is slowing it down.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 14) {
                Feature(symbol: "waveform.path.ecg", colors: Theme.cpu, title: "Live monitoring",
                        text: "CPU, memory, GPU, storage, network, battery\(store.sensorsAvailable ? ", temperatures and fans" : "") with history, in the window and in the menu bar.")
                Feature(symbol: "sparkles", colors: Theme.cleanup, title: "Cleanup you can read",
                        text: "Every file is listed before anything happens. Your own files only ever go to the Trash.")
                Feature(symbol: "brain", colors: Theme.ai, title: "Built for local AI",
                        text: "See which models Ollama or LM Studio hold in memory, what your model libraries weigh on disk, and how big a model fits right now.")
                Feature(symbol: "lock.shield", colors: Theme.health, title: "Private by design",
                        text: "No account, no analytics, no network calls. Free and open source under the MIT license.")
            }
            .padding(.bottom, 24)

            Divider().overlay(Theme.hairline).padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                if store.access.isRequired {
                    SetupRow(done: store.access.hasAccess, title: "Home folder access",
                             detail: "Needed for Cleanup, Apps and the storage map in the App Store edition.") {
                        Button(store.access.hasAccess ? "Granted" : "Choose Folder…") { store.access.requestAccess() }
                            .buttonStyle(GhostButtonStyle(compact: true)).disabled(store.access.hasAccess)
                    }
                }
                SetupRow(done: store.alerts.authorization == .granted, title: "Notifications",
                         detail: "Optional. Alerts for sustained CPU, memory pressure, low disk space or heat.") {
                    Button(store.alerts.authorization == .granted ? "Enabled" : "Allow…") { store.alerts.requestAuthorization() }
                        .buttonStyle(GhostButtonStyle(compact: true)).disabled(store.alerts.authorization == .granted)
                }
                SetupRow(done: store.launchAtLogin, title: "Open at login",
                         detail: "Keeps the menu bar readout available after a restart. Can be changed in Settings.") {
                    Button(store.launchAtLogin ? "On" : "Turn On") { _ = store.setLaunchAtLogin(true) }
                        .buttonStyle(GhostButtonStyle(compact: true)).disabled(store.launchAtLogin)
                }
            }

            Spacer()
            HStack {
                Link("Privacy policy", destination: Links.privacy).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Spacer()
                Button("Get Started") {
                    store.settings.hasSeenWelcome = true
                    AuxiliaryWindow.close(id: "welcome")
                }
                .buttonStyle(GlowButtonStyle(colors: Theme.cpu))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .padding(.top, 12)
        .background(Theme.background)
    }

    private struct Feature: View {
        let symbol: String
        let colors: [Color]
        let title: String
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: symbol, colors: colors, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct SetupRow<Control: View>: View {
        let done: Bool
        let title: String
        let detail: String
        @ViewBuilder var control: () -> Control

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Theme.good : Theme.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                control()
            }
        }
    }
}

private struct AboutView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 72)
            VStack(spacing: 2) {
                Text("Overdrive").font(Theme.rounded(22, .bold)).foregroundStyle(Theme.text)
                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber)) · \(store.capabilities.editionName)")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Text("A free, open-source system monitor and cleaner for the Mac. It reads everything from the kernel and IORegistry on this machine and sends nothing anywhere.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Link("Source code", destination: Links.repository)
                Link("MIT license", destination: Links.license)
                Link("Privacy", destination: Links.privacy)
            }
            .font(.system(size: 12, weight: .medium))
            Text("© 2026 Damion Rashford").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
        .padding(28)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
