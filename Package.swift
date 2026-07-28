// swift-tools-version: 6.2

import PackageDescription
import Foundation

let ghosttyFrameworkPath = "Vendor/GhosttyKit.xcframework"
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
// build-libghostty.sh touches this manifest after generating the framework so
// SwiftPM re-evaluates this file-existence-dependent target graph.
let hasGhosttyFramework = FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent(ghosttyFrameworkPath).path
)
var terminalDependencies: [Target.Dependency] = ["BreathCore"]
var targets: [Target] = [
    .target(name: "BreathCore"),
    .target(name: "BreathTestSupport"),
    .target(
        name: "BreathAgents",
        dependencies: [
            "BreathCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    ),
    .target(
        name: "BreathAutomation",
        dependencies: [
            "BreathAgents",
            "BreathCore",
        ],
        linkerSettings: [
            .linkedFramework("IOKit"),
        ]
    ),
    .target(
        name: "BreathSkills",
        dependencies: [
            "BreathAgents",
            "BreathCore",
            .product(name: "Yams", package: "Yams"),
        ]
    ),
    .target(
        name: "BreathPersistence",
        dependencies: [
            "BreathAutomation",
            "BreathSkills",
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
            "BreathAutomation",
            "BreathCore",
            "BreathPersistence",
            "BreathSkills",
            "BreathTerminal",
            "BreathUpdates",
        ],
        resources: [.process("Resources")],
        linkerSettings: [
            .linkedFramework("Network"),
            .linkedFramework("Security"),
        ]
    ),
    .testTarget(
        name: "BreathCoreTests",
        dependencies: ["BreathCore"]
    ),
    .testTarget(
        name: "BreathAutomationTests",
        dependencies: [
            "BreathAutomation",
            "BreathCore",
        ]
    ),
    .testTarget(
        name: "BreathPersistenceTests",
        dependencies: [
            "BreathAgents",
            "BreathAutomation",
            "BreathCore",
            "BreathPersistence",
        ]
    ),
    .testTarget(
        name: "BreathAgentsTests",
        dependencies: [
            "BreathAgents",
            "BreathCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]
    ),
    .testTarget(
        name: "BreathSkillsTests",
        dependencies: ["BreathSkills"]
    ),
    .testTarget(
        name: "BreathTerminalTests",
        dependencies: ["BreathCore", "BreathTerminal", "BreathTestSupport"]
    ),
    .testTarget(
        name: "BreathUpdatesTests",
        dependencies: ["BreathUpdates"]
    ),
    .testTarget(
        name: "BreathAppTests",
        dependencies: [
            "BreathApp",
            "BreathCore",
            "BreathPersistence",
            "BreathTerminal",
            "BreathTestSupport",
        ]
    ),
]

let package = Package(
    name: "Breath",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BreathCore", targets: ["BreathCore"]),
        .library(name: "BreathAgents", targets: ["BreathAgents"]),
        .library(name: "BreathAutomation", targets: ["BreathAutomation"]),
        .library(name: "BreathSkills", targets: ["BreathSkills"]),
        .library(name: "BreathPersistence", targets: ["BreathPersistence"]),
        .library(name: "BreathTerminal", targets: ["BreathTerminal"]),
        .library(name: "BreathUpdates", targets: ["BreathUpdates"]),
        .executable(name: "Breath", targets: ["BreathApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.4"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: targets
)
