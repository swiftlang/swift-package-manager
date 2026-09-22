// swift-tools-version: 6.5
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

let package = Package(
    name: "AndroidApp",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-system", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AndroidApp",
            dependencies: [
                // To pick up the shared library
                .product(name: "MyAppAndroid", package: "swift-sdl"),
                // To pick up the jar file
                //.product(name: "SwiftSDL3", package: "swift-sdl"),
            ],
            plugins: ["ApkBuilderPlugin"]
        ),
        .plugin(
            name: "ApkBuilderPlugin",
            capability: .buildTool(),
            dependencies: ["ApkBuilder"]
        ),
        .executableTarget(
            name: "ApkBuilder",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        )
    ]
)
