/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageDescription

let package = Package(
    name: "SwiftPM",
    
    /**
     The following is parsed by our bootstrap script, so
     if you make changes here please check the boostrap still
     succeeds! Thanks.
    */
    targets: [
        // The `PackageDescription` module is special, it defines the API which
        // is available to the `Package.swift` manifest files.
        Target(
            /** Package Definition API */
            name: "PackageDescription",
            dependencies: []),

        // MARK: Support libraries
        
        Target(
            /** Cross-platform access to bare `libc` functionality. */
            name: "libc",
            dependencies: []),
        Target(
            /** “Swifty” POSIX functions from libc */
            name: "POSIX",
            dependencies: ["libc"]),
        Target(
            /** Abstractions for common operations, should migrate to Basic */
            name: "Utility",
            dependencies: ["POSIX"]),
        Target(
            /** Basic support library */
            name: "Basic",
            dependencies: ["libc", "POSIX"]),

        // MARK: Project Model
        
        Target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["Basic", "PackageDescription", "Utility"]),
        Target(
            /** Manifest serialization */
            name: "ManifestSerializer",
            dependencies: ["Basic", "PackageDescription", "PackageModel"]),
        Target(
            /** Turns Packages into Modules & Products */
            name: "Transmute",
            dependencies: ["Basic", "PackageDescription", "PackageModel"]),

        // MARK: Miscellaneous

        Target(
            /** Provides cFlags and link flags from .pc files for a System Module */
            name: "PkgConfig",
            dependencies: ["Basic", "Utility", "PackageModel"]),
        Target(
            /** Common components of both executables */
            name: "Multitool",
            dependencies: ["Basic", "PackageModel"]),

        // MARK: Package Manager Functionality
        
        Target(
            /** Fetches Packages and their dependencies */
            name: "Get",
            dependencies: ["Basic", "PackageDescription", "PackageModel"]),
        Target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["Basic", "PackageModel", "PkgConfig"]),
        Target(
            /** Generates Xcode projects */
            name: "Xcodeproj",
            dependencies: ["Basic", "PackageModel", "PkgConfig"]),

        // MARK: Tools
        
        Target(
            /** The main executable provided by SwiftPM */
            name: "swift-build",
            dependencies: ["Basic", "ManifestSerializer", "Get", "Transmute", "Build", "Multitool", "Xcodeproj"]),
        Target(
            /** Runs package tests */
            name: "swift-test",
            dependencies: ["Basic", "Multitool"]),
    ])


// otherwise executables are auto-determined you could
// prevent this by asking for the auto-determined list
// here and editing it.

let dylib = Product(name: "PackageDescription", type: .Library(.Dynamic), modules: "PackageDescription")

products.append(dylib)
