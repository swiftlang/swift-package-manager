// swift-tools-version: 6.5

import PackageDescription

let package = Package(
    name: "swift-sdl",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "SDL",
            targets: ["SDL"]
        ),
        .library(
            name: "AndroidExample",
            type: .dynamic,
            targets: ["AndroidExample"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.5.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "603.0.1"),
    ],
    targets: [
        .externalTarget(
            name: "SDL",
            location: .local(path: "../SDL"),
            cSettings: [
                .headerSearchPath("include"),
            ],
            plugins: [
                "CMakeBuilderPlugin"
            ]
        ),
        .plugin(
            name: "CMakeBuilderPlugin",
            capability: .buildTool,
            dependencies: ["CMakeBuilder"]
        ),
        .executableTarget(
            name: "CMakeBuilder",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .target(
            name: "SwiftSDL3",
            dependencies: [
                "SDL",
            ],
            linkerSettings: [
                .linkedLibrary("SDL3"),
                .linkedFramework("CoreMedia", .when(platforms: [.macOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.macOS])),
                .linkedFramework("Cocoa", .when(platforms: [.macOS])),
                .linkedFramework("UniformTypeIdentifiers", .when(platforms: [.macOS])),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("ForceFeedback", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("CoreAudio", .when(platforms: [.macOS])),
                .linkedFramework("AudioToolbox", .when(platforms: [.macOS])),
                .linkedFramework("AVFoundation", .when(platforms: [.macOS])),
                .linkedFramework("Foundation", .when(platforms: [.macOS])),
                .linkedFramework("GameController", .when(platforms: [.macOS])),
                .linkedFramework("Metal", .when(platforms: [.macOS])),
                .linkedFramework("UserNotifications", .when(platforms: [.macOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS])),
                .linkedFramework("Security", .when(platforms: [.macOS])),
                .linkedFramework("CoreHaptics", .when(platforms: [.macOS])),
            ],
            plugins: ["SwiftSDLGenPlugin"]
        ),
        .plugin(
            name: "SwiftSDLGenPlugin",
            capability: .buildTool,
            dependencies: ["SwiftSDLGenerator"]
        ),
        .executableTarget(
            name: "SwiftSDLGenerator",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
        ),
        .target(
            name: "AndroidExample",
            dependencies: [
                "SwiftSDL3",
            ]
        ),
        .testTarget(
            name: "SDLTests",
            dependencies: ["SwiftSDL3"]
        ),
    ],
)
