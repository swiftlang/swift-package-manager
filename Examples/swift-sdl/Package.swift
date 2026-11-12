// swift-tools-version: 6.4
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-sdl",
    platforms: [
        .macOS(.v26), .iOS(.v26)
    ],
    products: [
        .library(
            name: "MyAppCore",
            targets: ["MyAppCore"]
        ),
        .library(
            name: "MyAppAndroid",
            type: .dynamic,
            targets: ["MyAppCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.5.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "604.0.0"),
        .package(url: "https://github.com/apple/swift-system", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SDL3",
            cSettings: [
                .headerSearchPath("../../SDL/include"),
            ],
            linkerSettings: [
                .linkedLibrary("SDL3"),
                .unsafeFlags(["-L", "SDL/build-android"], .when(platforms: [.android])),

                .linkedFramework("CoreMedia", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("CoreVideo", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("CoreAudio", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("AudioToolbox", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("AVFoundation", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("Foundation", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("GameController", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("Metal", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.macOS, .iOS])),
                .linkedFramework("CoreHaptics", .when(platforms: [.macOS, .iOS])),
                .linkedLibrary("pthread", .when(platforms: [.macOS, .iOS])),

                .linkedLibrary("m", .when(platforms: [.macOS, .iOS, .android])),

                .linkedFramework("Cocoa", .when(platforms: [.macOS])),
                .linkedFramework("UniformTypeIdentifiers", .when(platforms: [.macOS])),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("ForceFeedback", .when(platforms: [.macOS])),
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("UserNotifications", .when(platforms: [.macOS])),
                .linkedFramework("Security", .when(platforms: [.macOS])),

                .linkedFramework("CoreBluetooth", .when(platforms: [.iOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.iOS])),
                .linkedFramework("CoreMotion", .when(platforms: [.iOS])),
                .linkedFramework("OpenGLES", .when(platforms: [.iOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),

                .linkedLibrary("OpenSLES", .when(platforms: [.android])),
                .linkedLibrary("dl", .when(platforms: [.android])),
                .linkedLibrary("log", .when(platforms: [.android])),
                .linkedLibrary("android", .when(platforms: [.android])),
                .linkedLibrary("GLESv1_CM", .when(platforms: [.android])),
                .linkedLibrary("GLESv2", .when(platforms: [.android])),

                .linkedLibrary("kernel32", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
                .linkedLibrary("winmm", .when(platforms: [.windows])),
                .linkedLibrary("imm32", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("oleaut32", .when(platforms: [.windows])),
                .linkedLibrary("version", .when(platforms: [.windows])),
                .linkedLibrary("uuid", .when(platforms: [.windows])),
                .linkedLibrary("advapi32", .when(platforms: [.windows])),
                .linkedLibrary("setupapi", .when(platforms: [.windows])),
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                .linkedLibrary("dinput8", .when(platforms: [.windows])),
            ]
        ),
        .plugin(
            name: "SwiftSDLGenPlugin",
            capability: .buildTool,
            dependencies: ["SwiftSDLGenerator"]
        ),
        .executableTarget(
            name: "SwiftSDLGenerator",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .macro(
            name: "SwiftSDLMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "SwiftSDL",
            dependencies: [
                "SDL3",
                "SwiftSDLMacros",
            ],
            cSettings: [
                .headerSearchPath("../../SDL/include"),
            ],
            plugins: [
                "SwiftSDLGenPlugin",
            ]
        ),
        .target(
            name: "MyAppCore",
            dependencies: [
                "SwiftSDL",
                // For testing purposes only
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            cSettings: [
                .headerSearchPath("../../SDL/include"),
            ]
        ),
        .executableTarget(
            name: "MyAppExe",
            dependencies: ["MyAppCore"],
            cSettings: [
                .headerSearchPath("../../SDL/include"),
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "SDL/build-macos"], .when(platforms: [.macOS])),
            ]
        ),
    ]
)
