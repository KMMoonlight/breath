// swift-tools-version: 6.2

import PackageDescription
import Foundation

let ghosttyFrameworkPath = "Vendor/GhosttyKit.xcframework"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let hasGhosttyFramework = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(ghosttyFrameworkPath).path
)
var terminalDependencies: [Target.Dependency] = ["BreathCore"]
var targets: [Target] = [
    .target(name: "BreathCore"),
    .target(
        name: "BreathAgents",
        dependencies: ["BreathCore"]
    ),
    .target(
        name: "BreathPersistence",
        dependencies: [
            "BreathCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    ),
    .target(
        name: "BreathUpdates",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
        ]
    ),
]

if hasGhosttyFramework {
    targets.append(.binaryTarget(name: "GhosttyKit", path: ghosttyFrameworkPath))
    terminalDependencies.append("GhosttyKit")
}

targets.append(
    .target(
        name: "BreathTerminal",
        dependencies: terminalDependencies,
        swiftSettings: hasGhosttyFramework ? [.define("BREATH_HAS_GHOSTTY")] : [],
        linkerSettings: hasGhosttyFramework
            ? [
                .linkedFramework("Carbon"),
                .linkedFramework("CoreText"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
            : []
    )
)

targets += [
    .executableTarget(
        name: "BreathApp",
        dependencies: [
            "BreathAgents",
            "BreathCore",
            "BreathPersistence",
            "BreathTerminal",
            "BreathUpdates",
        ]
    ),
    .testTarget(
        name: "BreathCoreTests",
        dependencies: ["BreathCore"]
    ),
    .testTarget(
        name: "BreathPersistenceTests",
        dependencies: ["BreathAgents", "BreathCore", "BreathPersistence"]
    ),
    .testTarget(
        name: "BreathAgentsTests",
        dependencies: ["BreathAgents", "BreathCore"]
    ),
    .testTarget(
        name: "BreathTerminalTests",
        dependencies: ["BreathCore", "BreathTerminal"]
    ),
    .testTarget(
        name: "BreathUpdatesTests",
        dependencies: ["BreathUpdates"]
    ),
]

let package = Package(
    name: "Breath",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BreathCore", targets: ["BreathCore"]),
        .library(name: "BreathAgents", targets: ["BreathAgents"]),
        .library(name: "BreathPersistence", targets: ["BreathPersistence"]),
        .library(name: "BreathTerminal", targets: ["BreathTerminal"]),
        .library(name: "BreathUpdates", targets: ["BreathUpdates"]),
        .executable(name: "Breath", targets: ["BreathApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.4"),
    ],
    targets: targets
)
