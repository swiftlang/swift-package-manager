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
            dependencies: ["PackageDescription", "Utility"]),  //FIXME dependency on PackageDescription sucks
        Target(                                                //FIXME Utility is too general, we only need `Path`
            name: "ManifestParser",
            dependencies: ["PackageDescription", "PackageType"]),
        Target(
            /** Turns Packages into Modules & Products */
            name: "Transmute",
            dependencies: ["PackageDescription", "PackageType"]),
        Target(
            /** Fetches Packages and their dependencies */
            name: "Get",
            dependencies: ["ManifestParser"]),
        Target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: ["PackageType"]),
        Target(
            /** Common components of both executables */
            name: "Multitool",
            dependencies: ["PackageType"]),
        Target(
            name: "Xcodeproj",
            dependencies: ["PackageType"]),
        Target(
            name: "swift-build",
            dependencies: ["Get", "Transmute", "Build", "Multitool", "Xcodeproj"]),
        Target(
            name: "swift-test",
            dependencies: ["Multitool"]),
    ])


// otherwise executables are auto-determined you could
// prevent this by asking for the auto-determined list
// here and editing it.

let dylib = Product(name: "PackageDescription", type: .Library(.Dynamic), modules: "PackageDescription")

products.append(dylib)
