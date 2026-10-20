import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    static let background = Color(hex: 0x06070C)
    static let sidebar = Color(hex: 0x0A0B12)
    static let text = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
    static let hairline = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.07)

    static let good = Color(hex: 0x4ADE80)
    static let warn = Color(hex: 0xFBBF24)
    static let bad = Color(hex: 0xF87171)

    static let cpu = [Color(hex: 0x22D3EE), Color(hex: 0x3B82F6)]
    static let memory = [Color(hex: 0xE879F9), Color(hex: 0x8B5CF6)]
    static let gpu = [Color(hex: 0xFCD34D), Color(hex: 0xF97316)]
    static let disk = [Color(hex: 0x6EE7B7), Color(hex: 0x10B981)]
    static let network = [Color(hex: 0xFDA4AF), Color(hex: 0xF43F5E)]
    static let processes = [Color(hex: 0xBEF264), Color(hex: 0x22C55E)]
    static let cleanup = [Color(hex: 0x5EEAD4), Color(hex: 0x0EA5E9)]
    static let maintenance = [Color(hex: 0xFDBA74), Color(hex: 0xEC4899)]
    static let settings = [Color(hex: 0xCBD5E1), Color(hex: 0x64748B)]
    static let health = [Color(hex: 0x86EFAC), Color(hex: 0x22D3EE)]

    static let download = Color(hex: 0x38BDF8)
    static let upload = Color(hex: 0xF472B6)

    /// Cool cyan at idle through amber to red when saturated.
    static func heat(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.35: Color(hex: 0x22D3EE)
        case ..<0.6: Color(hex: 0x60A5FA)
        case ..<0.8: Color(hex: 0xFBBF24)
        default: Color(hex: 0xF87171)
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
    case overview, cpu, memory, gpu, disk, network, processes, cleanup, maintenance, settings

    var id: String { rawValue }

    static let monitor: [Page] = [.overview, .cpu, .memory, .gpu, .disk, .network]
    static let optimize: [Page] = [.processes, .cleanup, .maintenance]

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .disk: "Storage"
        case .network: "Network"
        case .processes: "Processes"
        case .cleanup: "Cleanup"
        case .maintenance: "Maintenance"
        case .settings: "Settings"
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
        case .processes: "list.bullet.rectangle.portrait"
        case .cleanup: "sparkles"
        case .maintenance: "wrench.and.screwdriver"
        case .settings: "gearshape"
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
        case .processes: Theme.processes
        case .cleanup: Theme.cleanup
        case .maintenance: Theme.maintenance
        case .settings: Theme.settings
        }
    }
}
