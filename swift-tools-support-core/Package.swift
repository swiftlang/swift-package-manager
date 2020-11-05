// swift-tools-version:5.2

/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2019 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */


import PackageDescription

let package = Package(
    name: "swift-tools-support-core",
    products: [
        .library(
            name: "SwiftToolsSupport",
            type: .dynamic,
            targets: ["TSCBasic", "TSCUtility"]),
        .library(
            name: "SwiftToolsSupport-auto",
            targets: ["TSCBasic", "TSCUtility"]),

        .library(
            name: "TSCTestSupport",
            targets: ["TSCTestSupport"]),
        .executable(
            name: "TSCTestSupportExecutable",
            targets: ["TSCTestSupportExecutable"]),
    ],
    dependencies: [
        
    ],
    targets: [
        
        // MARK: Tools support core targets
        
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
            dependencies: ["TSCLibc", "TSCclibc"]),
        .target(
            /** Abstractions for common operations, should migrate to TSCBasic */
            name: "TSCUtility",
            dependencies: ["TSCBasic", "TSCclibc"]),
        
        // MARK: Additional Test Dependencies
        
        .target(
            /** Generic test support library */
            name: "TSCTestSupport",
            dependencies: ["TSCBasic", "TSCUtility"]),
        .target(
            /** Test support executable */
            name: "TSCTestSupportExecutable",
            dependencies: ["TSCBasic", "TSCUtility"]),
        
        
        // MARK: Tools support core tests
        
        .testTarget(
            name: "TSCBasicTests",
            dependencies: ["TSCTestSupport", "TSCTestSupportExecutable", "TSCclibc"]),
        .testTarget(
            name: "TSCBasicPerformanceTests",
            dependencies: ["TSCBasic", "TSCTestSupport"]),
        .testTarget(
            name: "TSCTestSupportTests",
            dependencies: ["TSCTestSupport"]),
        .testTarget(
            name: "TSCUtilityTests",
            dependencies: ["TSCUtility", "TSCTestSupport", "TSCTestSupportExecutable"]),
    ]
)

// FIXME: conditionalise these flags since SwiftPM 5.3 and earlier will crash
// for platforms they don't know about.
#if os(Windows)
  if let TSCBasic = package.targets.first(where: { $0.name == "TSCBasic" }) {
    TSCBasic.cxxSettings = [
      .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
    ]
    TSCBasic.linkerSettings = [
      .linkedLibrary("Pathcch", .when(platforms: [.windows])),
    ]
  }
#endif
