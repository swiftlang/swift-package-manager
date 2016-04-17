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
        Target(
            /** “Swifty” POSIX functions from libc */
            name: "POSIX",
            dependencies: ["libc"]),
        Target(
            /** Abstractions for common operations */
            name: "Utility",
            dependencies: ["POSIX"]),
        Target(
            /** Base types for the package-engine */
            name: "PackageType",
            dependencies: ["PackageDescription", "Utility"]),
        Target(
            name: "ManifestParser",
            dependencies: ["PackageDescription", "PackageType"]),
        Target(
            /** Turns Packages into Modules & Products */
            name: "Transmute",
            dependencies: ["PackageDescription", "PackageType"]),
        Target(
            /** Fetches Packages and their dependencies */
            name: "Get",
            dependencies: ["PackageDescription", "PackageType"]),
        Target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["PackageType"]),
        Target(
            /** Common components of both executables */
            name: "Multitool",
            dependencies: ["PackageType", "OptionsParser"]),
        Target(
            /** Generates Xcode projects */
            name: "Xcodeproj",
            dependencies: ["PackageType"]),
        Target(
            /** Command line options parser */
            name: "OptionsParser",
            dependencies: ["libc"]),
        Target(
            /** The main executable provided by SwiftPM */
            name: "swift-build",
            dependencies: ["ManifestParser", "Get", "Transmute", "Build", "Multitool", "Xcodeproj"]),
        Target(
            /** Runs package tests */
            name: "swift-test",
            dependencies: ["Multitool"]),
    ])


// otherwise executables are auto-determined you could
// prevent this by asking for the auto-determined list
// here and editing it.

let dylib = Product(name: "PackageDescription", type: .Library(.Dynamic), modules: "PackageDescription")

products.append(dylib)
