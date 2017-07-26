// swift-tools-version:4.0

/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription

let package = Package(
    name: "SwiftPM",
    products: [
        .library(
            name: "SwiftPM",
            type: .dynamic,
            targets: [
                "clibc",
                "libc",
                "POSIX",
                "Basic",
                "Utility",
                "SourceControl",
                "PackageDescription",
                "PackageDescription4",
                "PackageModel",
                "PackageLoading",
                "PackageGraph",
                "Build",
                "Xcodeproj",
                "Workspace"
            ]
        )
    ],
    targets: [
        // The `PackageDescription` targets are special, they define the API which
        // is available to the `Package.swift` manifest files.
        .target(
            /** Package Definition API version 3 */
            name: "PackageDescription",
            dependencies: []),
        .target(
            /** Package Definition API version 4 */
            name: "PackageDescription4",
            dependencies: []),

        // MARK: Support libraries
        
        .target(
            /** Shim target to import missing C headers in Darwin and Glibc modulemap. */
            name: "clibc",
            dependencies: []),
        .target(
            /** Cross-platform access to bare `libc` functionality. */
            name: "libc",
            dependencies: ["clibc"]),
        .target(
            /** “Swifty” POSIX functions from libc */
            name: "POSIX",
            dependencies: ["libc"]),
        .target(
            /** Basic support library */
            name: "Basic",
            dependencies: ["libc", "POSIX"]),
        .target(
            /** Abstractions for common operations, should migrate to Basic */
            name: "Utility",
            dependencies: ["POSIX", "Basic"]),
        .target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: ["Basic", "Utility"]),

        // MARK: Project Model
        
        .target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["Basic", "PackageDescription", "PackageDescription4", "Utility"]),
        .target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: ["Basic", "PackageDescription", "PackageDescription4", "PackageModel", "Utility"]),

        // MARK: Package Dependency Resolution
        
        .target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: ["Basic", "PackageLoading", "PackageModel", "SourceControl", "Utility"]),
        
        // MARK: Package Manager Functionality
        
        .target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["Basic", "PackageGraph"]),
        .target(
            /** Generates Xcode projects */
            name: "Xcodeproj",
            dependencies: ["Basic", "PackageGraph"]),
        .target(
            /** High level functionality */
            name: "Workspace",
            dependencies: ["Basic", "Build", "PackageGraph", "PackageModel", "SourceControl", "Xcodeproj"]),

        // MARK: Commands
        
        .target(
            /** High-level commands */
            name: "Commands",
            dependencies: ["Basic", "Build", "PackageGraph", "SourceControl", "Utility", "Xcodeproj", "Workspace"]),
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
            /** Test support library */
            name: "TestSupport",
            dependencies: ["Basic", "POSIX", "PackageGraph", "PackageLoading", "SourceControl", "Utility", "Commands"]),
        .target(
            /** Test support executable */
            name: "TestSupportExecutable",
            dependencies: ["Basic", "POSIX", "Utility"]),
        
        .testTarget(
            name: "BasicTests",
            dependencies: ["TestSupport", "TestSupportExecutable"]),
        .testTarget(
            name: "BasicPerformanceTests",
            dependencies: ["Basic", "TestSupport"]),
        .testTarget(
            name: "BuildTests",
            dependencies: ["Build", "TestSupport"]),
        .testTarget(
            name: "CommandsTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "swift-run", "Commands", "Workspace", "TestSupport"]),
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "TestSupport"]),
        .testTarget(
            name: "FunctionalTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "Basic", "Utility", "PackageModel", "TestSupport"]),
        .testTarget(
            name: "FunctionalPerformanceTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "swift-build", "swift-package", "TestSupport"]),
        .testTarget(
            name: "PackageDescriptionTests",
            dependencies: ["PackageDescription"]),
        .testTarget(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "TestSupport"],
            exclude: ["Inputs"]),
        .testTarget(
            name: "PackageLoadingPerformanceTests",
            dependencies: ["PackageLoading", "TestSupport"]),
        .testTarget(
            name: "PackageModelTests",
            dependencies: ["PackageModel"]),
        .testTarget(
            name: "PackageGraphTests",
            dependencies: ["PackageGraph", "TestSupport"]),
        .testTarget(
            name: "PackageGraphPerformanceTests",
            dependencies: ["PackageGraph", "TestSupport"]),
        .testTarget(
            name: "POSIXTests",
            dependencies: ["POSIX", "TestSupport"]),
        .testTarget(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "TestSupport"]),
        .testTarget(
            name: "TestSupportTests",
            dependencies: ["TestSupport"]),
        .testTarget(
            name: "UtilityTests",
            dependencies: ["Utility", "TestSupport", "TestSupportExecutable"]),
        .testTarget(
            name: "XcodeprojTests",
            dependencies: ["Xcodeproj", "TestSupport"]),
    ],
    swiftLanguageVersions: [3]
)
