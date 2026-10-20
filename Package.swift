// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Overdrive",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Overdrive", targets: ["Overdrive"]),
        .library(name: "OverdriveCore", targets: ["OverdriveCore"]),
    ],
    targets: [
        .target(name: "OverdriveCore", swiftSettings: v5),
        .executableTarget(name: "Overdrive", dependencies: ["OverdriveCore"], swiftSettings: v5),
        .testTarget(name: "OverdriveCoreTests", dependencies: ["OverdriveCore"], swiftSettings: v5),
    ]
)
