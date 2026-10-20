import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that follows the window's appearance, so the same token reads well in Light and Dark Mode.
    static func adaptive(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkOpacity : lightOpacity)
        })
    }
}

/// The visual system: one surface, one accent pair per metric, three text tones, one hairline.
/// Every token adapts to Light and Dark Mode; views never hard-code white or black.
enum Theme {
    static let background = Color.adaptive(light: 0xF3F4F7, dark: 0x0B0C10)
    static let sidebar = Color.adaptive(light: 0xE9EBF0, dark: 0x0F1015)
    static let cardTop = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.92, darkOpacity: 0.058)
    static let cardBottom = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.84, darkOpacity: 0.022)
    static let text = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.9, darkOpacity: 0.92)
    static let secondary = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.6, darkOpacity: 0.6)
    static let tertiary = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.42, darkOpacity: 0.38)
    static let hairline = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.09, darkOpacity: 0.08)
    static let track = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.08)
    /// Subtle, hover and pressed fills for custom controls.
    static let fill = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.06)
    static let fillHover = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.1)
    static let fillPressed = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.12, darkOpacity: 0.14)
    static let border = Color.adaptive(light: 0x0B0C10, dark: 0xFFFFFF, lightOpacity: 0.12, darkOpacity: 0.1)
    static let onAccent = Color.white

    static let good = Color.adaptive(light: 0x15803D, dark: 0x4ADE80)
    static let warn = Color.adaptive(light: 0xB45309, dark: 0xFBBF24)
    static let bad = Color.adaptive(light: 0xDC2626, dark: 0xF87171)

    private static func pair(light: (UInt32, UInt32), dark: (UInt32, UInt32)) -> [Color] {
        [Color.adaptive(light: light.0, dark: dark.0), Color.adaptive(light: light.1, dark: dark.1)]
    }

    static let cpu = pair(light: (0x0284C7, 0x1D4ED8), dark: (0x38BDF8, 0x3B82F6))
    static let memory = pair(light: (0x9333EA, 0x6D28D9), dark: (0xC084FC, 0x8B5CF6))
    static let gpu = pair(light: (0xD97706, 0xC2410C), dark: (0xFBBF24, 0xF97316))
    static let disk = pair(light: (0x059669, 0x047857), dark: (0x34D399, 0x10B981))
    static let network = pair(light: (0xE11D48, 0xBE123C), dark: (0xFB7185, 0xF43F5E))
    static let battery = pair(light: (0x65A30D, 0x4D7C0F), dark: (0xA3E635, 0x65A30D))
    static let sensors = pair(light: (0xEA580C, 0xB91C1C), dark: (0xFB923C, 0xEF4444))
    static let ai = pair(light: (0x0D9488, 0x0F766E), dark: (0x2DD4BF, 0x0D9488))
    static let processes = pair(light: (0x65A30D, 0x15803D), dark: (0xA3E635, 0x22C55E))
    static let cleanup = pair(light: (0x0D9488, 0x0369A1), dark: (0x5EEAD4, 0x0EA5E9))
    static let apps = pair(light: (0x2563EB, 0x4338CA), dark: (0x93C5FD, 0x6366F1))
    static let maintenance = pair(light: (0xC2410C, 0xBE185D), dark: (0xFDBA74, 0xEC4899))
    static let health = pair(light: (0x16A34A, 0x0E7490), dark: (0x86EFAC, 0x22D3EE))
    static let danger = pair(light: (0xE11D48, 0xBE123C), dark: (0xFB7185, 0xE11D48))

    static let download = Color.adaptive(light: 0x0284C7, dark: 0x38BDF8)
    static let upload = Color.adaptive(light: 0xDB2777, dark: 0xF472B6)

    /// Cool at idle through amber to red when saturated.
    static func heat(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.35: Color.adaptive(light: 0x0284C7, dark: 0x38BDF8)
        case ..<0.6: Color.adaptive(light: 0x2563EB, dark: 0x60A5FA)
        case ..<0.8: warn
        default: bad
        }
    }

    /// Temperature bands in °C.
    static func thermal(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: Color.adaptive(light: 0x0284C7, dark: 0x38BDF8)
        case ..<80: good
        case ..<95: warn
        default: bad
        }
    }

    static func severity(_ level: Int) -> Color {
        [good, warn, bad][max(0, min(2, level))]
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum Page: String, CaseIterable, Identifiable, Hashable {
    case overview, cpu, memory, gpu, disk, network, battery, sensors
    case processes, ai, cleanup, apps, maintenance

    var id: String { rawValue }

    static let monitor: [Page] = [.overview, .cpu, .memory, .gpu, .disk, .network, .battery, .sensors]
    static let optimize: [Page] = [.processes, .ai, .cleanup, .apps, .maintenance]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .disk: "Storage"
        case .network: "Network"
        case .battery: "Battery"
        case .sensors: "Sensors"
        case .processes: "Processes"
        case .ai: "AI Workloads"
        case .cleanup: "Cleanup"
        case .apps: "Apps"
        case .maintenance: "Maintenance"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "cube.transparent"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.75percent"
        case .sensors: "thermometer.medium"
        case .processes: "list.bullet.rectangle.portrait"
        case .ai: "brain"
        case .cleanup: "sparkles"
        case .apps: "square.stack.3d.up"
        case .maintenance: "wrench.and.screwdriver"
        }
    }

    var accent: [Color] {
        switch self {
        case .overview: Theme.health
        case .cpu: Theme.cpu
        case .memory: Theme.memory
        case .gpu: Theme.gpu
        case .disk: Theme.disk
        case .network: Theme.network
        case .battery: Theme.battery
        case .sensors: Theme.sensors
        case .processes: Theme.processes
        case .ai: Theme.ai
        case .cleanup: Theme.cleanup
        case .apps: Theme.apps
        case .maintenance: Theme.maintenance
        }
    }
}
