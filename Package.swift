// swift-tools-version:5.1

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription
import class Foundation.ProcessInfo

// We default to a 10.10 minimum deployment target for clients of libSwiftPM,
// but allow overriding it when building for a toolchain.

let macOSPlatform: SupportedPlatform
if let deploymentTarget = ProcessInfo.processInfo.environment["SWIFTPM_MACOS_DEPLOYMENT_TARGET"] {
    macOSPlatform = .macOS(deploymentTarget)
} else {
    macOSPlatform = .macOS(.v10_10)
}

let package = Package(
    name: "SwiftPM",
    platforms: [macOSPlatform],
    products: [
        // The `libSwiftPM` set of interfaces to programatically work with Swift
        // packages.
        //
        // NOTE: This API is *unstable* and may change at any time.
        .library(
            name: "SwiftPM",
            type: .dynamic,
            targets: [
                "SourceControl",
                "SPMLLBuild",
                "LLBuildManifest",
                "PackageModel",
                "PackageLoading",
                "PackageGraph",
                "Build",
                "Xcodeproj",
                "Workspace"
            ]
        ),
        .library(
            name: "SwiftPM-auto",
            targets: [
                "SourceControl",
                "SPMLLBuild",
                "LLBuildManifest",
                "PackageModel",
                "PackageLoading",
                "PackageGraph",
                "Build",
                "Xcodeproj",
                "Workspace"
            ]
        ),

        .library(
            name: "XCBuildSupport",
            targets: ["XCBuildSupport"]
        ),

        .library(
            name: "PackageDescription",
            type: .dynamic,
            targets: ["PackageDescription"]
        ),
    ],
    targets: [
        // The `PackageDescription` targets define the API which is available to
        // the `Package.swift` manifest files. We build the latest API version
        // here which is used when building and running swiftpm without the
        // bootstrap script.
        .target(
            /** Package Definition API */
            name: "PackageDescription",
            swiftSettings: [
                .define("PACKAGE_DESCRIPTION_4_2"),
            ]),

        // MARK: SwiftPM specific support libraries

        .target(
            /** The llbuild manifest model */
            name: "LLBuildManifest",
            dependencies: ["SwiftToolsSupport-auto"]),

        .target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: ["SwiftToolsSupport-auto"]),
        .target(
            /** Shim for llbuild library */
            name: "SPMLLBuild",
            dependencies: ["SwiftToolsSupport-auto"]),

        // MARK: Project Model

        .target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["SwiftToolsSupport-auto"]),
        .target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: ["SwiftToolsSupport-auto", "PackageModel", "SPMLLBuild"]),

        // MARK: Package Dependency Resolution

        .target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: ["SwiftToolsSupport-auto", "PackageLoading", "PackageModel", "SourceControl"]),

        // MARK: Package Manager Functionality

        .target(
            /** Builds Modules and Products */
            name: "SPMBuildCore",
            dependencies: ["SwiftToolsSupport-auto", "PackageGraph"]),
        .target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["SwiftToolsSupport-auto", "SPMBuildCore", "PackageGraph", "LLBuildManifest", "SwiftDriver"]),
        .target(
            /** Support for building using Xcode's build system */
            name: "XCBuildSupport",
            dependencies: ["SPMBuildCore", "PackageGraph"]),

        .target(
            /** Generates Xcode projects */
            name: "Xcodeproj",
            dependencies: ["SwiftToolsSupport-auto", "PackageGraph"]),
        .target(
            /** High level functionality */
            name: "Workspace",
            dependencies: ["SwiftToolsSupport-auto", "Build", "PackageGraph", "PackageModel", "SourceControl", "Xcodeproj"]),

        // MARK: Commands

        .target(
            /** High-level commands */
            name: "Commands",
            dependencies: ["SwiftToolsSupport-auto", "Build", "PackageGraph", "SourceControl", "Xcodeproj", "Workspace", "XCBuildSupport", "ArgumentParser"]),
        .target(
            /** The main executable provided by SwiftPM */
            name: "swift-package",
            dependencies: ["Commands"]),
        .target(
            /** Builds packages */
            name: "swift-build",
            dependencies: ["Commands"]),
        .target(
            /** Runs package tests */
            name: "swift-test",
            dependencies: ["Commands"]),
        .target(
            /** Runs an executable product */
            name: "swift-run",
            dependencies: ["Commands"]),
        .target(
            /** Shim tool to find test names on OS X */
            name: "swiftpm-xctest-helper",
            dependencies: [],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../lib/swift/macosx"], .when(platforms: [.macOS])),
            ]),

        // MARK: Additional Test Dependencies

        .target(
            /** SwiftPM test support library */
            name: "SPMTestSupport",
            dependencies: ["SwiftToolsSupport-auto", "TSCTestSupport", "PackageGraph", "PackageLoading", "SourceControl", "Commands", "XCBuildSupport"]),

        // MARK: SwiftPM tests

        .testTarget(
            name: "BuildTests",
            dependencies: ["Build", "SPMTestSupport"]),
        .testTarget(
            name: "CommandsTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "swift-run", "Commands", "Workspace", "SPMTestSupport"]),
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "SPMTestSupport"]),
        .testTarget(
            name: "FunctionalTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "PackageModel", "SPMTestSupport"]),
        .testTarget(
            name: "FunctionalPerformanceTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "SPMTestSupport"]),
        .testTarget(
            name: "PackageDescription4Tests",
            dependencies: ["PackageDescription"]),
        .testTarget(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "SPMTestSupport"],
            exclude: ["Inputs"]),
        .testTarget(
            name: "PackageLoadingPerformanceTests",
            dependencies: ["PackageLoading", "SPMTestSupport"]),
        .testTarget(
            name: "PackageModelTests",
            dependencies: ["PackageModel", "SPMTestSupport"]),
        .testTarget(
            name: "PackageGraphTests",
            dependencies: ["PackageGraph", "SPMTestSupport"]),
        .testTarget(
            name: "PackageGraphPerformanceTests",
            dependencies: ["PackageGraph", "SPMTestSupport"]),
        .testTarget(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "SPMTestSupport"]),
        .testTarget(
            name: "XcodeprojTests",
            dependencies: ["Xcodeproj", "SPMTestSupport"]),
        .testTarget(
            name: "XCBuildSupportTests",
            dependencies: ["XCBuildSupport", "SPMTestSupport"]),

        // Examples (These are built to ensure they stay up to date with the API.)
        .target(
            name: "package-info",
            dependencies: ["PackageModel", "PackageLoading", "PackageGraph", "Workspace"],
            path: "Examples/package-info/Sources/package-info"
        )
    ],
    swiftLanguageVersions: [.v5]
)

// Add package dependency on llbuild when not bootstrapping.
//
// When bootstrapping SwiftPM, we can't use llbuild as a package dependency it
// will provided by whatever build system (SwiftCI, bootstrap script) is driving
// the build process. So, we only add these dependencies if SwiftPM is being
// built directly using SwiftPM. It is a bit unfortunate that we've add the
// package dependency like this but there is no other good way of expressing
// this right now.


if ProcessInfo.processInfo.environment["SWIFTPM_LLBUILD_FWK"] == nil {
    if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
        package.dependencies += [
            .package(url: "https://github.com/apple/swift-llbuild.git", .branch("master")),
        ]
    } else {
        // In Swift CI, use a local path to llbuild to interoperate with tools
        // like `update-checkout`, which control the sources externally.
        package.dependencies += [
            .package(path: "../llbuild"),
        ]
    }
    package.targets.first(where: { $0.name == "SPMLLBuild" })!.dependencies += ["llbuildSwift"]
}

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("master")),
        // The 'swift-argument-parser' version declared here must match that
        // used by 'swift-driver' and 'sourcekit-lsp'. Please coordinate
        // dependency version changes here with those projects.
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            .upToNextMinor(from: "0.3.1")),
        .package(url: "https://github.com/apple/swift-driver.git", .branch("master")),
    ]
} else {
    package.dependencies += [
        .package(path: "./swift-tools-support-core"),
        .package(path: "../swift-argument-parser"),
        .package(path: "../swift-driver"),
    ]
}
