// swift-tools-version: 6.0

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("InternalImportsByDefault"), // SE-0409: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
]

let package = Package(
    name: "BinaryArtifactAudit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "binary-artifact-audit", targets: ["BinaryArtifactAuditExec"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2"),
    ],
    targets: [
        .executableTarget(
            name: "BinaryArtifactAuditExec",
            dependencies: [
                .target(name: "BinaryArtifactAudit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "BinaryArtifactAudit",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "BinaryArtifactAuditTests",
            dependencies: [.target(name: "BinaryArtifactAudit")],
            resources: [
                .copy("TestBundles")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
