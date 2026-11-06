// swift-tools-version: 999.0

import PackageDescription

let package = Package(
    name: "AnyAppleOS",
    platforms: [
        .anyAppleOS(.v26),
        .macOS(.v27),
    ],
    targets: [
        .target(
            name: "AnyAppleOS",
            swiftSettings: [
                .define("APPLE", .when(platforms: [.anyAppleOS])),
                .define("APPLE_OR_LINUX", .when(platforms: [.linux, .anyAppleOS, .macOS])),
            ]
        ),
    ]
)
