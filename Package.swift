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
    
    /**
     The following is parsed by our bootstrap script, so
     if you make changes here please check the bootstrap still
     succeeds! Thanks.
    */
    targets: [
        // The `PackageDescription` targets are special, they define the API which
        // is available to the `Package.swift` manifest files.
        Target(
            /** Package Definition API version 3 */
            name: "PackageDescription",
            dependencies: []),
        Target(
            /** Package Definition API version 4 */
            name: "PackageDescription4",
            dependencies: []),

        // MARK: Support libraries
        
        Target(
            /** Shim target to import missing C headers in Darwin and Glibc modulemap. */
            name: "clibc",
            dependencies: []),
        Target(
            /** Cross-platform access to bare `libc` functionality. */
            name: "libc",
            dependencies: ["clibc"]),
        Target(
            /** “Swifty” POSIX functions from libc */
            name: "POSIX",
            dependencies: ["libc"]),
        Target(
            /** Basic support library */
            name: "Basic",
            dependencies: ["libc", "POSIX"]),
        Target(
            /** Abstractions for common operations, should migrate to Basic */
            name: "Utility",
            dependencies: ["POSIX", "Basic"]),
        Target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: ["Basic", "Utility"]),

        // MARK: Project Model
        
        Target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["Basic", "PackageDescription", "PackageDescription4", "Utility"]),
        Target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: ["Basic", "PackageDescription", "PackageDescription4", "PackageModel", "Utility"]),

        // MARK: Package Dependency Resolution
        
        Target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: ["Basic", "PackageLoading", "PackageModel", "SourceControl", "Utility"]),
        
        // MARK: Package Manager Functionality
        
        Target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["Basic", "PackageGraph"]),
        Target(
            /** Generates Xcode projects */
            name: "Xcodeproj",
            dependencies: ["Basic", "PackageGraph"]),
        Target(
            /** High level functionality */
            name: "Workspace",
            dependencies: ["Basic", "Build", "PackageGraph", "PackageModel", "SourceControl", "Xcodeproj"]),

        // MARK: Commands
        
        Target(
            /** High-level commands */
            name: "Commands",
            dependencies: ["Basic", "Build", "PackageGraph", "SourceControl", "Utility", "Xcodeproj", "Workspace"]),
        Target(
            /** The main executable provided by SwiftPM */
            name: "swift-package",
            dependencies: ["Commands"]),
        Target(
            /** Builds packages */
            name: "swift-build",
            dependencies: ["Commands"]),
        Target(
            /** Runs package tests */
            name: "swift-test",
            dependencies: ["Commands"]),
        Target(
            /** Shim tool to find test names on OS X */
            name: "swiftpm-xctest-helper",
            dependencies: []),

        // MARK: Additional Test Dependencies

        Target(
            /** Test support library */
            name: "TestSupport",
            dependencies: ["Basic", "POSIX", "PackageGraph", "PackageLoading", "SourceControl", "Utility", "Commands"]),
        Target(
            /** Test support executable */
            name: "TestSupportExecutable",
            dependencies: ["Basic", "POSIX", "Utility"]),
        
        Target(
            name: "BasicTests",
            dependencies: ["TestSupport", "TestSupportExecutable"]),
        Target(
            name: "BasicPerformanceTests",
            dependencies: ["Basic", "TestSupport"]),
        Target(
            name: "BuildTests",
            dependencies: ["Build", "TestSupport"]),
        Target(
            name: "CommandsTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "Commands", "Workspace", "TestSupport"]),
        Target(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "TestSupport"]),
        Target(
            name: "FunctionalTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "Basic", "Utility", "PackageModel", "TestSupport"]),
        Target(
            name: "FunctionalPerformanceTests",
            dependencies: ["swift-build", "swift-package", "swift-test", "swift-build", "swift-package", "TestSupport"]),
        Target(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "TestSupport"]),
        Target(
            name: "PackageLoadingPerformanceTests",
            dependencies: ["PackageLoading", "TestSupport"]),
        Target(
            name: "PackageGraphTests",
            dependencies: ["PackageGraph", "TestSupport"]),
        Target(
            name: "PackageGraphPerformanceTests",
            dependencies: ["PackageGraph", "TestSupport"]),
        Target(
            name: "POSIXTests",
            dependencies: ["POSIX", "TestSupport"]),
        Target(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "TestSupport"]),
        Target(
            name: "UtilityTests",
            dependencies: ["Utility", "TestSupport", "TestSupportExecutable"]),
        Target(
            name: "XcodeprojTests",
            dependencies: ["Xcodeproj", "TestSupport"]),
    ],
    swiftLanguageVersions: [3],
    exclude: [
        "Tests/PackageLoadingTests/Inputs",
    ]
)


// The executable products are automatically determined by SwiftPM; any target
// that contains a `main.swift` source file results in an implicit executable
// product.

// SwiftPM Library -- provides package management functionality to clients
products.append(
    Product(
        name: "SwiftPM",
        type: .Library(.Dynamic),
        modules: [
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
)
