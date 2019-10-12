// swift-tools-version:5.1

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription

let package = Package(
    name: "SwiftPM",
    products: [
        // The `libSwiftPM` set of interfaces to programatically work with Swift
        // packages.
        //
        // NOTE: This API is *unstable* and may change at any time.
        .library(
            name: "SwiftPM",
            type: .dynamic,
            targets: [
                "TSCclibc",
                "TSCLibc",
                "TSCBasic",
                "TSCUtility",
                "SourceControl",
                "SPMLLBuild",
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
                "TSCclibc",
                "TSCLibc",
                "TSCBasic",
                "TSCUtility",
                "SourceControl",
                "SPMLLBuild",
                "PackageModel",
                "PackageLoading",
                "PackageGraph",
                "Build",
                "Xcodeproj",
                "Workspace"
            ]
        ),

        // Collection of general purpose utilities.
        //
        // NOTE: This product consists of *unsupported*, *unstable* API. These
        // APIs are implementation details of the package manager. Depend on it
        // at your own risk.
        .library(
            name: "TSCUtility",
            targets: [
                "TSCclibc",
                "TSCLibc",
                "TSCBasic",
                "TSCUtility",
            ]
        ),
    ],
    targets: [
        // The `PackageDescription` targets are special, they define the API which
        // is available to the `Package.swift` manifest files.
        .target(
            /** Package Definition API version 4 */
            name: "PackageDescription4",
            dependencies: []),

        // MARK: Tools support core targets
        // keep up to date with https://github.com/apple/swift-tools-support-core

        .target(
            /** Shim target to import missing C headers in Darwin and Glibc modulemap. */
            name: "TSCclibc",
            dependencies: []),
        .target(
            /** Cross-platform access to bare `libc` functionality. */
            name: "TSCLibc",
            dependencies: []),
        .target(
            /** TSCBasic support library */
            name: "TSCBasic",
            dependencies: ["TSCLibc"]),
        .target(
            /** Abstractions for common operations, should migrate to TSCBasic */
            name: "TSCUtility",
            dependencies: ["TSCBasic", "TSCclibc"]),
        
        // MARK: SwiftPM specific support libraries
        
        .target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: ["TSCBasic", "TSCUtility"]),
        .target(
            /** Shim for llbuild library */
            name: "SPMLLBuild",
            dependencies: ["TSCBasic", "TSCUtility"]),

        // MARK: Project Model

        .target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["TSCBasic", "TSCUtility"]),
        .target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: ["TSCBasic", "PackageModel", "TSCUtility", "SPMLLBuild"]),

        // MARK: Package Dependency Resolution

        .target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: ["TSCBasic", "PackageLoading", "PackageModel", "SourceControl", "TSCUtility"]),

        // MARK: Package Manager Functionality

        .target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["TSCBasic", "PackageGraph"]),
        .target(
            /** Generates Xcode projects */
            name: "Xcodeproj",
            dependencies: ["TSCBasic", "PackageGraph"]),
        .target(
            /** High level functionality */
            name: "Workspace",
            dependencies: ["TSCBasic", "Build", "PackageGraph", "PackageModel", "SourceControl", "TSCUtility", "Xcodeproj"]),

        // MARK: Commands

        .target(
            /** High-level commands */
            name: "Commands",
            dependencies: ["TSCBasic", "Build", "PackageGraph", "SourceControl", "TSCUtility", "Xcodeproj", "Workspace"]),
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
            dependencies: []),

        // MARK: Additional Test Dependencies

        .target(
            /** Generic test support library */
            name: "TSCTestSupport",
            dependencies: ["TSCBasic", "TSCUtility"]),
        .target(
            /** Test support executable */
            name: "TSCTestSupportExecutable",
            dependencies: ["TSCBasic", "TSCUtility"]),
        .target(
            /** SwiftPM test support library */
            name: "SPMTestSupport",
            dependencies: ["TSCTestSupport", "PackageGraph", "PackageLoading", "SourceControl", "Commands"]),

        // MARK: Tools support core tests
        // keep up to date with https://github.com/apple/swift-tools-support-core
        
        .testTarget(
            name: "TSCBasicTests",
            dependencies: ["TSCTestSupport", "TSCTestSupportExecutable"]),
        .testTarget(
            name: "TSCBasicPerformanceTests",
            dependencies: ["TSCBasic", "TSCTestSupport"]),
        .testTarget(
            name: "TSCTestSupportTests",
            dependencies: ["TSCTestSupport"]),
        .testTarget(
            name: "TSCUtilityTests",
            dependencies: ["TSCUtility", "TSCTestSupport", "TSCTestSupportExecutable"]),
        
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
            dependencies: ["swift-build", "swift-package", "swift-test", "TSCBasic", "TSCUtility", "PackageModel", "SPMTestSupport"]),
        .testTarget(
            name: "FunctionalPerformanceTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "SPMTestSupport"]),
        .testTarget(
            name: "PackageDescription4Tests",
            dependencies: ["PackageDescription4"]),
        .testTarget(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "SPMTestSupport"],
            exclude: ["Inputs"]),
        .testTarget(
            name: "PackageLoadingPerformanceTests",
            dependencies: ["PackageLoading", "SPMTestSupport"]),
        .testTarget(
            name: "PackageModelTests",
            dependencies: ["PackageModel"]),
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

import class Foundation.ProcessInfo

if ProcessInfo.processInfo.environment["SWIFTPM_BOOTSTRAP"] == nil {
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

if ProcessInfo.processInfo.environment["SWIFTPM_BUILD_PACKAGE_EDITOR"] != nil {
    package.targets += [
        .target(name: "SPMPackageEditor", dependencies: ["Workspace", "SwiftSyntax"]),
        .target(name: "swiftpm-manifest-tool", dependencies: ["SPMPackageEditor"]),
        .testTarget(name: "SPMPackageEditorTests", dependencies: ["SPMPackageEditor", "SPMTestSupport"]),
    ]
    package.dependencies += [
        .package(path: "../swift-syntax"),
    ]
}
