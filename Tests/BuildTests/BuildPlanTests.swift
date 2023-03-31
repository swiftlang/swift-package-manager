//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import Build
import PackageLoading
@testable import PackageGraph
@testable import PackageModel
import SPMBuildCore
import SPMTestSupport
import SwiftDriver
import TSCBasic
import Workspace
import XCTest
import enum TSCUtility.Diagnostics
@_implementationOnly import DriverSupport

final class BuildPlanTests: XCTestCase {
    let inputsDir = AbsolutePath(path: #file).parentDirectory.appending(components: "Inputs")
    private let driverSupport = DriverSupport()

    /// The j argument.
    private var j: String {
        return "-j3"
    }

    func testDuplicateProductNamesWithNonDefaultLibsThrowError() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/FooLogging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        XCTAssertThrowsError(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.static), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )) { error in
            var diagnosed = false
            if let realError = error as? PackageGraphError,
               realError.description == "multiple products named 'Logging' in: 'barpkg', 'foopkg'" {
                diagnosed = true
            }
            XCTAssertTrue(diagnosed)
        }
    }

    func testDuplicateProductNamesWithADylib() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/FooLogging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }

    func testDuplicateProductNamesUpstream1() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/FooLogging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift",
                                    "/bazPkg/Sources/BazLogging/file.swift",
                                    "/xPkg/Sources/XUtils/file.swift",
                                    "/yPkg/Sources/YUtils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "bazPkg",
                    path: .init(path: "/bazPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BazLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BazLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/bazPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "bazPkg"
                                                                 ),
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "xPkg",
                    path: .init(path: "/xPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["XUtils"]),
                    ],
                    targets: [
                        TargetDescription(name: "XUtils", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "yPkg",
                    path: .init(path: "/yPkg"),
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["YUtils"]),
                    ],
                    targets: [
                        TargetDescription(name: "YUtils", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/xPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/yPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Utils",
                                                                  package: "xPkg"
                                                                 ),
                                                         .product(name: "Utils",
                                                                  package: "yPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(6)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BazLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "XUtils" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "YUtils" })
    }

    func testDuplicateProductNamesUpstream2() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/Logging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift",
                                    "/bazPkg/Sources/BazLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "bazPkg",
                    path: .init(path: "/bazPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BazLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BazLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/bazPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(name: "Logging",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "bazPkg"
                                                                 ),
                                          ]),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(4)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Logging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BazLogging" })
    }

    func testDuplicateProductNamesChained() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/FooLogging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                          ]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }
    func testDuplicateProductNamesThrowError() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/FooLogging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()

        XCTAssertThrowsError(try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    toolsVersion: .v5_8,
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )) { error in
            var diagnosed = false
            if let realError = error as? PackageGraphError,
               realError.description == "multiple products named 'Logging' in: 'barpkg', 'foopkg'" {
                diagnosed = true
            }
            XCTAssertTrue(diagnosed)
        }
    }

    func testDuplicateProductNamesAllowed() throws {
        let fs = InMemoryFileSystem(emptyFiles:
                                        "/thisPkg/Sources/exe/main.swift",
                                    "/fooPkg/Sources/FooLogging/file.swift",
                                    "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: .init(path: "/fooPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: .init(path: "/barPkg"),
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: .init(path: "/thisPkg"),
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/fooPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/barPkg"), requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe",
                                          dependencies: [.product(name: "Logging",
                                                                  package: "fooPkg"
                                                                 ),
                                                         .product(name: "Logging",
                                                                  package: "barPkg"
                                                                 ),
                                          ],
                                          type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: try BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }

    func testPackageNameFlag() throws {
        let isFlagSupportedInDriver = try driverSupport.checkToolchainDriverFlags(flags: ["package-name"], toolchain: UserToolchain.default, fileSystem: localFileSystem)
        try fixture(name: "Miscellaneous/PackageNameFlag") { fixturePath in
            let (stdout, _) = try executeSwiftBuild(fixturePath.appending("appPkg"), extraArgs: ["-v"])
            XCTAssertMatch(stdout, .contains("-module-name Foo"))
            XCTAssertMatch(stdout, .contains("-module-name Zoo"))
            XCTAssertMatch(stdout, .contains("-module-name Bar"))
            XCTAssertMatch(stdout, .contains("-module-name Baz"))
            XCTAssertMatch(stdout, .contains("-module-name App"))
            XCTAssertMatch(stdout, .contains("-module-name exe"))
            if isFlagSupportedInDriver {
                XCTAssertMatch(stdout, .contains("-package-name apppkg"))
                XCTAssertMatch(stdout, .contains("-package-name foopkg"))
                // the flag is not supported in old toolsversions
                XCTAssertNoMatch(stdout, .contains("-package-name barpkg"))
            } else {
                XCTAssertNoMatch(stdout, .contains("-package-name"))
            }
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }

    func testTargetGroupToPackageNameFlag() throws {
        let isFlagSupportedInDriver = try driverSupport.checkToolchainDriverFlags(flags: ["package-name"], toolchain: UserToolchain.default, fileSystem: localFileSystem)
        try fixture(name: "Miscellaneous/TargetGrouping") { fixturePath in
            let (stdout, _) = try executeSwiftBuild(fixturePath.appending("libPkg"), extraArgs: ["-v"])
            if isFlagSupportedInDriver {
                let moduleFlag1 = stdout.range(of: "-module-name DataModel")
                XCTAssertNotNil(moduleFlag1)
                let stdoutNext1 = stdout[moduleFlag1!.upperBound...]
                let packageFlag1 = stdoutNext1.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag1)

                let moduleFlag2 = stdoutNext1.range(of: "-module-name DataManager")
                XCTAssertNotNil(moduleFlag2)
                XCTAssertTrue(packageFlag1!.upperBound < moduleFlag2!.lowerBound)
                let stdoutNext2 = stdoutNext1[moduleFlag2!.upperBound...]
                let packageFlag2 = stdoutNext2.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag2)

                let moduleFlag3 = stdoutNext2.range(of: "-module-name Core")
                XCTAssertNotNil(moduleFlag3)
                XCTAssertTrue(packageFlag2!.upperBound < moduleFlag3!.lowerBound)
                let stdoutNext3 = stdoutNext2[moduleFlag3!.upperBound...]
                let packageFlag3 = stdoutNext3.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag3)

                let moduleFlag4 = stdoutNext3.range(of: "-module-name MainLib")
                XCTAssertNotNil(moduleFlag4)
                XCTAssertTrue(packageFlag3!.upperBound < moduleFlag4!.lowerBound)
                let stdoutNext4 = stdoutNext3[moduleFlag4!.upperBound...]
                let packageFlag4 = stdoutNext4.range(of: "-package-name libpkg")
                XCTAssertNotNil(packageFlag4)

                let moduleFlag5 = stdoutNext4.range(of: "-module-name ExampleApp")
                XCTAssertNotNil(moduleFlag5)
                XCTAssertTrue(packageFlag4!.upperBound < moduleFlag5!.lowerBound)
                let stdoutNext5 = stdoutNext4[moduleFlag5!.upperBound...]
                let packageFlag5 = stdoutNext5.range(of: "-package-name")
                XCTAssertNil(packageFlag5)
            } else {
                XCTAssertNoMatch(stdout, .contains("-package-name"))
            }
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }

    func testBasicSwiftPackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertMatch(lib, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        let linkArguments = [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "exe.build", "exe.swiftmodule").pathString,
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "lib.swiftmodule").pathString,
        ]
      #elseif os(Windows)
        let linkArguments = [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            // "-static-stdlib",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ]
      #else
        let linkArguments = [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-static-stdlib",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ]
      #endif

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), linkArguments)

      #if os(macOS)
        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("can be downloaded"), severity: .warning)
        }
      #else
        XCTAssertNoDiagnostics(observability.diagnostics)
      #endif
    }

    func testExplicitSwiftPackageBuild() throws {
        // <rdar://82053045> Fix and re-enable SwiftPM test `testExplicitSwiftPackageBuild`
        try XCTSkipIf(true)
        try withTemporaryDirectory { path in
            // Create a test package with three targets:
            // A -> B -> C
            let fs = localFileSystem
            try fs.changeCurrentWorkingDirectory(to: path)
            let testDirPath = path.appending("ExplicitTest")
            let buildDirPath = path.appending(".build")
            let sourcesPath = testDirPath.appending("Sources")
            let aPath = sourcesPath.appending("A")
            let bPath = sourcesPath.appending("B")
            let cPath = sourcesPath.appending("C")
            try fs.createDirectory(testDirPath)
            try fs.createDirectory(buildDirPath)
            try fs.createDirectory(sourcesPath)
            try fs.createDirectory(aPath)
            try fs.createDirectory(bPath)
            try fs.createDirectory(cPath)
            let main = aPath.appending("main.swift")
            let aSwift = aPath.appending("A.swift")
            let bSwift = bPath.appending("B.swift")
            let cSwift = cPath.appending("C.swift")
            try localFileSystem.writeFileContents(main) {
              $0 <<< "baz();"
            }
            try localFileSystem.writeFileContents(aSwift) {
                $0 <<< "import B;"
                $0 <<< "import C;"
                $0 <<< "public func baz() { bar() }"
            }
            try localFileSystem.writeFileContents(bSwift) {
                $0 <<< "import C;"
                $0 <<< "public func bar() { foo() }"
            }
            try localFileSystem.writeFileContents(cSwift) {
                $0 <<< "public func foo() {}"
            }

            // Plan package build with explicit module build
            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadPackageGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "ExplicitTest",
                        path: testDirPath,
                        targets: [
                            TargetDescription(name: "A", dependencies: ["B"]),
                            TargetDescription(name: "B", dependencies: ["C"]),
                            TargetDescription(name: "C", dependencies: []),
                        ]),
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            do {
                let plan = try BuildPlan(
                    buildParameters: mockBuildParameters(
                        buildPath: buildDirPath,
                        config: .release,
                        toolchain: UserToolchain.default,
                        destinationTriple: UserToolchain.default.triple,
                        useExplicitModuleBuild: true
                    ),
                    graph: graph,
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )


                let yaml = buildDirPath.appending("release.yaml")
                let llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
                try llbuild.generateManifest(at: yaml)
                let contents: String = try localFileSystem.readFileContents(yaml)

                // A few basic checks
                XCTAssertMatch(contents, .contains("-disable-implicit-swift-modules"))
                XCTAssertMatch(contents, .contains("-fno-implicit-modules"))
                XCTAssertMatch(contents, .contains("-explicit-swift-module-map-file"))
                XCTAssertMatch(contents, .contains("A-dependencies"))
                XCTAssertMatch(contents, .contains("B-dependencies"))
                XCTAssertMatch(contents, .contains("C-dependencies"))
            } catch Driver.Error.unableToDecodeFrontendTargetInfo {
                // If the toolchain being used is sufficiently old, the integrated driver
                // will not be able to parse the `-print-target-info` output. In which case,
                // we cannot yet rely on the integrated swift driver.
                // This effectively guards the test from running on unsupported, older toolchains.
                throw XCTSkip()
            }
        }
    }

    func testSwiftConditionalDependency() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "PkgLib", "lib.swift").pathString,
            "/ExtPkg/Sources/ExtLib/lib.swift",
            "/PlatformPkg/Sources/PlatformLib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/ExtPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/PlatformPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .target(name: "PkgLib", condition: PackageConditionDescription(
                                platformNames: ["linux", "android"],
                                config: nil
                            ))
                        ]),
                        TargetDescription(name: "PkgLib", dependencies: [
                            .product(name: "ExtLib", package: "ExtPkg", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            )),
                            .product(name: "PlatformLib", package: "PlatformPkg", condition: PackageConditionDescription(
                                platformNames: ["linux"]
                            ))
                        ]),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "ExtPkg",
                    path: .init(path: "/ExtPkg"),
                    products: [
                        ProductDescription(name: "ExtLib", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "PlatformPkg",
                    path: .init(path: "/PlatformPkg"),
                    platforms: [PlatformDescription(name: "macos", version: "50.0")],
                    products: [
                        ProductDescription(name: "PlatformLib", type: .library(.automatic), targets: ["PlatformLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "PlatformLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        do {
            let plan = try BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .linux,
                    configuration: .release
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            let buildPath: AbsolutePath = plan.buildParameters.dataPath.appending(components: "release")

            let linkedFileList: String = try fs.readFileContents("/path/to/build/release/exe.product/Objects.LinkFileList")
            XCTAssertMatch(linkedFileList, .contains("PkgLib"))
            XCTAssertNoMatch(linkedFileList, .contains("ExtLib"))

            let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "release.yaml")
            try fs.createDirectory(yaml.parentDirectory, recursive: true)
            let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            try llbuild.generateManifest(at: yaml)
            let contents: String = try fs.readFileContents(yaml)
            XCTAssertMatch(contents, .contains("""
                    inputs: ["\(Pkg.appending(components: "Sources", "exe", "main.swift").escapedPathString())","\(buildPath.appending(components: "PkgLib.swiftmodule").escapedPathString())"]
                """))

        }

        do {
            let plan = try BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .macOS,
                    configuration: .debug
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            let linkedFileList: String = try fs.readFileContents("/path/to/build/debug/exe.product/Objects.LinkFileList")
            XCTAssertNoMatch(linkedFileList, .contains("PkgLib"))
            XCTAssertNoMatch(linkedFileList, .contains("ExtLib"))

            let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
            try fs.createDirectory(yaml.parentDirectory, recursive: true)
            let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            try llbuild.generateManifest(at: yaml)
            let contents: String = try fs.readFileContents(yaml)
            XCTAssertMatch(contents, .contains("""
                    inputs: ["\(Pkg.appending(components: "Sources", "exe", "main.swift").escapedPathString())"]
                """))
        }
    }

    func testBasicExtPackages() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Tests/ATargetTests/foo.swift",
            "/B/Sources/BTarget/foo.swift",
            "/B/Tests/BTargetTests/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                        TargetDescription(name: "ATargetTests", dependencies: ["ATarget"], type: .test),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: .init(path: "/B"),
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                        TargetDescription(name: "BTargetTests", dependencies: ["BTarget"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        XCTAssertEqual(Set(result.productMap.keys), ["APackageTests"])
      #if os(macOS)
        XCTAssertEqual(Set(result.targetMap.keys), ["ATarget", "BTarget", "ATargetTests"])
      #else
        XCTAssertEqual(Set(result.targetMap.keys), [
            "APackageTests",
            "APackageDiscoveredTests",
            "ATarget",
            "ATargetTests",
            "BTarget"
        ])
      #endif
    }

    func testBasicReleasePackage() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(config: .release),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "release")

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-O", "-g", .equal(j), "-DSWIFT_PACKAGE", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-g", "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-dead_strip",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-Xlinker", "-debug",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "/OPT:REF",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-g",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "--gc-sections",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testBasicReleasePackageNoDeadStrip() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(config: .release, linkerDeadStrip: false),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "release")

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-O", "-g", .equal(j), "-DSWIFT_PACKAGE", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-g",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-Xlinker", "-debug",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-g",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testBasicClangPackage() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")
        let ExtPkg: AbsolutePath = AbsolutePath("/ExtPkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.c").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.S").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString,
            ExtPkg.appending(components: "Sources", "extlib", "extlib.c").pathString,
            ExtPkg.appending(components: "Sources", "extlib", "include", "ext.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    dependencies: [
                        .localSourceControl(path: try .init(validating: ExtPkg.pathString), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: ["ExtPkg"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "ExtPkg",
                    path: try .init(validating: ExtPkg.pathString),
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["extlib"]),
                    ],
                    targets: [
                        TargetDescription(name: "extlib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let ext = try result.target(for: "extlib").clangTarget()
        var args: [String] = []

      #if os(macOS)
        args += ["-fobjc-arc"]
      #endif
        args += ["-target", defaultTargetTriple]
        args += ["-g"]
#if os(Windows)
        args += ["-gcodeview"]
#endif
        args += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks"]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        args += ["-fmodules", "-fmodule-name=extlib"]
#endif
        args += ["-I", ExtPkg.appending(components: "Sources", "extlib", "include").pathString]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        args += ["-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"]
#endif
        XCTAssertEqual(try ext.basicArguments(isCXX: false), args)
        XCTAssertEqual(try ext.objects, [buildPath.appending(components: "extlib.build", "extlib.c.o")])
        XCTAssertEqual(ext.moduleMap, buildPath.appending(components: "extlib.build", "module.modulemap"))

        let exe = try result.target(for: "exe").clangTarget()
        args = []

      #if os(macOS)
        args += ["-fobjc-arc", "-target", defaultTargetTriple]
      #else
        args += ["-target", defaultTargetTriple]
      #endif

        args += ["-g"]
#if os(Windows)
        args += ["-gcodeview"]
#endif
        args += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks"]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        args += ["-fmodules", "-fmodule-name=exe"]
#endif
        args += [
            "-I", Pkg.appending(components: "Sources", "exe", "include").pathString,
            "-I", Pkg.appending(components: "Sources", "lib", "include").pathString,
            "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))",
            "-I", ExtPkg.appending(components: "Sources", "extlib", "include").pathString,
            "-fmodule-map-file=\(buildPath.appending(components: "extlib.build", "module.modulemap"))",
        ]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        args += ["-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"]
#endif
        XCTAssertEqual(try exe.basicArguments(isCXX: false), args)
        XCTAssertEqual(try exe.objects, [buildPath.appending(components: "exe.build", "main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #endif

      let linkedFileList: String = try fs.readFileContents(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))
      XCTAssertEqual(linkedFileList, """
          \(buildPath.appending(components: "exe.build", "main.c.o"))
          \(buildPath.appending(components: "extlib.build", "extlib.c.o"))
          \(buildPath.appending(components: "lib.build", "lib.c.o"))

          """)
    }

    func testClangConditionalDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/PkgLib/lib.c",
            "/Pkg/Sources/PkgLib/lib.S",
            "/Pkg/Sources/PkgLib/include/lib.h",
            "/ExtPkg/Sources/ExtLib/extlib.c",
            "/ExtPkg/Sources/ExtLib/include/ext.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/ExtPkg"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .target(name: "PkgLib", condition: PackageConditionDescription(
                                platformNames: ["linux", "android"],
                                config: nil
                            ))
                        ]),
                        TargetDescription(name: "PkgLib", dependencies: [
                            .product(name: "ExtPkg", package: "ExtPkg", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            ))
                        ]),
                    ]),
                Manifest.createLocalSourceControlManifest(
                    displayName: "ExtPkg",
                    path: .init(path: "/ExtPkg"),
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        do {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .linux,
                    configuration: .release
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let exeArguments = try result.target(for: "exe").clangTarget().basicArguments(isCXX: false)
            XCTAssert(exeArguments.contains { $0.contains("PkgLib") })
            XCTAssert(exeArguments.allSatisfy { !$0.contains("ExtLib") })

            let libArguments = try result.target(for: "PkgLib").clangTarget().basicArguments(isCXX: false)
            XCTAssert(libArguments.allSatisfy { !$0.contains("ExtLib") })
        }

        do {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: BuildEnvironment(
                    platform: .macOS,
                    configuration: .debug
                )),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let arguments = try result.target(for: "exe").clangTarget().basicArguments(isCXX: false)
            XCTAssert(arguments.allSatisfy { !$0.contains("PkgLib") && !$0.contains("ExtLib")  })

            let libArguments = try result.target(for: "PkgLib").clangTarget().basicArguments(isCXX: false)
            XCTAssert(libArguments.contains { $0.contains("ExtLib") })
        }
    }

    func testCLanguageStandard() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.cpp").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "libx.cpp").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    cLanguageStandard: "gnu99",
                    cxxLanguageStandard: "c++1z",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-lc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-lstdc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
        ])
      #endif

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains(#"-std=gnu99","-c","\#(Pkg.appending(components: "Sources", "lib", "lib.c").escapedPathString())"#))
        XCTAssertMatch(contents, .contains(#"-std=c++1z","-c","\#(Pkg.appending(components: "Sources", "lib", "libx.cpp").escapedPathString())"#))
    }

    func testSwiftCMixed() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let lib = try result.target(for: "lib").clangTarget()
        var args: [String] = []

      #if os(macOS)
        args += ["-fobjc-arc", "-target", defaultTargetTriple]
      #else
        args += ["-target", defaultTargetTriple]
      #endif

        args += ["-g"]
#if os(Windows)
        args += ["-gcodeview"]
#endif
        args += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks"]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        args += ["-fmodules", "-fmodule-name=lib"]
#endif
        args += ["-I", Pkg.appending(components: "Sources", "lib", "include").pathString]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        args += ["-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"]
#endif
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.c.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, [.anySequence, "-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG","-Xcc", "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))", "-Xcc", "-I", "-Xcc", "\(Pkg.appending(components: "Sources", "lib", "include"))", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/debug/exe.build/exe.swiftmodule",
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testSwiftCAsmMixed() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/lib.S",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    toolsVersion: .v5,
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.target(for: "lib").clangTarget()
        XCTAssertEqual(try lib.objects, [
            AbsolutePath("/path/to/build/debug/lib.build/lib.S.o"),
            AbsolutePath("/path/to/build/debug/lib.build/lib.c.o")
        ])
    }

    func testREPLArguments() throws {
        let Dep = AbsolutePath("/Dep")
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/swiftlib/lib.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h",
            Dep.appending(components: "Sources", "Dep", "dep.swift").pathString,
            Dep.appending(components: "Sources", "CDep", "cdep.c").pathString,
            Dep.appending(components: "Sources", "CDep", "include", "head.h").pathString,
            Dep.appending(components: "Sources", "CDep", "include", "module.modulemap").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Dep"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["swiftlib"]),
                        TargetDescription(name: "swiftlib", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: ["Dep"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: .init(path: "/Dep"),
                    products: [
                        ProductDescription(name: "Dep", type: .library(.automatic), targets: ["Dep"]),
                    ],
                    targets: [
                        TargetDescription(name: "Dep", dependencies: ["CDep"]),
                        TargetDescription(name: "CDep", dependencies: []),
                    ]),
            ],
            createREPLProduct: true,
                                         observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let buildPath: AbsolutePath = plan.buildParameters.dataPath.appending(components: "debug")

        XCTAssertEqual(try plan.createREPLArguments().sorted(), ["-I\(Dep.appending(components: "Sources", "CDep", "include"))", "-I\(buildPath)", "-I\(buildPath.appending(components: "lib.build"))", "-L\(buildPath)", "-lpkg__REPL", "repl"])

        XCTAssertEqual(plan.graph.allProducts.map({ $0.name }).sorted(), [
            "Dep",
            "exe",
            "pkg__REPL"
        ])
    }

    func testTestModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/Foo/foo.swift",
            "/Pkg/Tests/\(SwiftTarget.defaultTestEntryPointName)",
            "/Pkg/Tests/FooTests/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
      #if os(macOS)
        result.checkTargetsCount(2)
      #else
        // On non-Apple platforms, when a custom entry point file is present (e.g. XCTMain.swift), there is one additional target for the synthesized test entry point.
        result.checkTargetsCount(3)
      #endif

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let foo = try result.target(for: "Foo").swiftTarget().compileArguments()
        XCTAssertMatch(foo, [.anySequence, "-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

        let fooTests = try result.target(for: "FooTests").swiftTarget().compileArguments()
        XCTAssertMatch(fooTests, [.anySequence, "-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        let version = MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "PkgPackageTests.xctest", "Contents", "MacOS", "PkgPackageTests").pathString,
            "-module-name", "PkgPackageTests",
            "-Xlinker", "-bundle",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../",
            "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", "\(hostTriple.tripleString(forPlatformVersion: version))",
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "Foo.swiftmodule").pathString,
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "FooTests.swiftmodule").pathString,
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "PkgPackageTests.xctest").pathString,
            "-module-name", "PkgPackageTests",
            "-emit-executable",
            "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "PkgPackageTests.xctest").pathString,
            "-module-name", "PkgPackageTests",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testConcurrencyInOS() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "12.0"),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(config: .release),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "release")

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()

        XCTAssertMatch(exe, [.anySequence, "-swift-version", "4", "-O", "-g", .equal(j), "-DSWIFT_PACKAGE", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-g",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-dead_strip",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", hostTriple.tripleString(forPlatformVersion: "12.0"),
        ])
      #endif
    }

    func testParseAsLibraryFlagForExe() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            // executable has a single source file not named `main.swift`, without @main.
            "/Pkg/Sources/exe1/foo.swift",
            // executable has a single source file named `main.swift`, without @main.
            "/Pkg/Sources/exe2/main.swift",
            // executable has a single source file not named `main.swift`, with @main.
            "/Pkg/Sources/exe3/foo.swift",
            // executable has a single source file named `main.swift`, with @main
            "/Pkg/Sources/exe4/main.swift",
            // executable has a single source file named `comments.swift`, with @main in comments
            "/Pkg/Sources/exe5/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments
            "/Pkg/Sources/exe6/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments
            "/Pkg/Sources/exe7/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments
            "/Pkg/Sources/exe8/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments
            "/Pkg/Sources/exe9/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments and not in comments
            "/Pkg/Sources/exe10/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments and not in comments
            "/Pkg/Sources/exe11/comments.swift",
            // executable has a single source file named `comments.swift`, with @main in comments and not in comments
            "/Pkg/Sources/exe12/comments.swift",
            // executable has multiple source files.
            "/Pkg/Sources/exe13/bar.swift",
            "/Pkg/Sources/exe13/main.swift",
            // Snippet with top-level code
            "/Pkg/Snippets/TopLevelCodeSnippet.swift",
            // Snippet with @main
            "/Pkg/Snippets/AtMainSnippet.swift"
        )

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe3/foo.swift")) {
            """
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe4/main.swift")) {
            """
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe5/comments.swift")) {
            """
            // @main in comment
            print("hello world")
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe6/comments.swift")) {
            """
            /* @main in comment */
            print("hello world")
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe7/comments.swift")) {
            """
            /*
            @main in comment
            */
            print("hello world")
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe8/comments.swift")) {
            """
            /*
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            */
            print("hello world")
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe9/comments.swift")) {
            """
            /*@main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }*/
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe10/comments.swift")) {
            """
            // @main in comment
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe11/comments.swift")) {
            """
            /* @main in comment */
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        }

        try fs.writeFileContents(AbsolutePath("/Pkg/Sources/exe12/comments.swift")) {
            """
            /*
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }*/
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        }

        try fs.writeFileContents("/Pkg/Snippets/TopLevelCodeSnippet.swift") {
            """
            struct Foo {
              init() {}
              func foo() {}
            }
            let foo = Foo()
            foo.foo()
            """
        }

        try fs.writeFileContents("/Pkg/Snippets/AtMainSnippet.swift") {
            """
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        }

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    toolsVersion: .v5_5,
                    targets: [
                        TargetDescription(name: "exe1", type: .executable),
                        TargetDescription(name: "exe2", type: .executable),
                        TargetDescription(name: "exe3", type: .executable),
                        TargetDescription(name: "exe4", type: .executable),
                        TargetDescription(name: "exe5", type: .executable),
                        TargetDescription(name: "exe6", type: .executable),
                        TargetDescription(name: "exe7", type: .executable),
                        TargetDescription(name: "exe8", type: .executable),
                        TargetDescription(name: "exe9", type: .executable),
                        TargetDescription(name: "exe10", type: .executable),
                        TargetDescription(name: "exe11", type: .executable),
                        TargetDescription(name: "exe12", type: .executable),
                        TargetDescription(name: "exe13", type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(15)
        result.checkTargetsCount(15)

        XCTAssertNoDiagnostics(observability.diagnostics)

        // single source file not named main, and without @main should not have -parse-as-library.
        let exe1 = try result.target(for: "exe1").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe1, ["-parse-as-library"])

         // single source file named main, and without @main should not have -parse-as-library.
        let exe2 = try result.target(for: "exe2").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe2, ["-parse-as-library"])

        // single source file not named main, with @main should have -parse-as-library.
        let exe3 = try result.target(for: "exe3").swiftTarget().emitCommandLine()
        XCTAssertMatch(exe3, ["-parse-as-library"])

        // single source file named main, with @main should have -parse-as-library.
        let exe4 = try result.target(for: "exe4").swiftTarget().emitCommandLine()
        XCTAssertMatch(exe4, ["-parse-as-library"])

        // multiple source files should not have -parse-as-library.
        let exe5 = try result.target(for: "exe5").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe5, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe6 = try result.target(for: "exe6").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe6, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe7 = try result.target(for: "exe7").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe7, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe8 = try result.target(for: "exe8").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe8, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe9 = try result.target(for: "exe9").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe9, ["-parse-as-library"])

        // @main in comment + non-comment should have -parse-as-library.
        let exe10 = try result.target(for: "exe10").swiftTarget().emitCommandLine()
        XCTAssertMatch(exe10, ["-parse-as-library"])

        // @main in comment + non-comment should have -parse-as-library.
        let exe11 = try result.target(for: "exe11").swiftTarget().emitCommandLine()
        XCTAssertMatch(exe11, ["-parse-as-library"])

        // @main in comment + non-comment should have -parse-as-library.
        let exe12 = try result.target(for: "exe12").swiftTarget().emitCommandLine()
        XCTAssertMatch(exe12, ["-parse-as-library"])

        // multiple source files should not have -parse-as-library.
        let exe13 = try result.target(for: "exe13").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(exe13, ["-parse-as-library"])

        // A snippet with top-level code should not have -parse-as-library.
        let topLevelCodeSnippet = try result.target(for: "TopLevelCodeSnippet").swiftTarget().emitCommandLine()
        XCTAssertNoMatch(topLevelCodeSnippet, ["-parse-as-library"])

        // A snippet with @main should have -parse-as-library
        let atMainSnippet = try result.target(for: "AtMainSnippet").swiftTarget().emitCommandLine()
        XCTAssertMatch(atMainSnippet, ["-parse-as-library"])
    }

    func testCModule() throws {
        let Clibgit = AbsolutePath("/Clibgit")

        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            Clibgit.appending(components: "module.modulemap").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    dependencies: [
                        .localSourceControl(path: try .init(validating: Clibgit.pathString), requirement: .upToNextMajor(from: "1.0.0"))
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "Clibgit",
                    path: .init(path: "/Clibgit")
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        XCTAssertMatch(try result.target(for: "exe").swiftTarget().compileArguments(), ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-Xcc", "-fmodule-map-file=\(Clibgit.appending(components: "module.modulemap"))", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

      #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "exe.build", "exe.swiftmodule").pathString,
        ])
      #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #endif
    }

    func testCppModule() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.cpp",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        let linkArgs = try result.buildProduct(for: "exe").linkArguments()

      #if os(macOS)
        XCTAssertMatch(linkArgs, ["-lc++"])
      #elseif !os(Windows)
        XCTAssertMatch(linkArgs, ["-lstdc++"])
      #endif
    }

    func testDynamicProducts() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/main.swift",
            "/Bar/Source/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: .init(path: "/Bar"),
                    products: [
                        ProductDescription(name: "Bar-Baz", type: .library(.dynamic), targets: ["Bar"]),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: []),
                    ]),
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: .init(path: "/Foo"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/Bar"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar-Baz"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: g,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let fooLinkArgs = try result.buildProduct(for: "Foo").linkArguments()
        let barLinkArgs = try result.buildProduct(for: "Bar-Baz").linkArguments()

      #if os(macOS)
        XCTAssertEqual(fooLinkArgs, [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Foo").pathString,
            "-module-name", "Foo",
            "-lBar-Baz",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "Foo.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "Foo.build", "Foo.swiftmodule").pathString
        ])

        XCTAssertEqual(barLinkArgs, [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "libBar-Baz.dylib").pathString,
            "-module-name", "Bar_Baz",
            "-emit-library",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/libBar-Baz.dylib",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "Bar-Baz.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "Bar.swiftmodule").pathString
        ])
      #elseif os(Windows)
        XCTAssertEqual(fooLinkArgs, [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Foo.exe").pathString,
            "-module-name", "Foo",
            "-lBar-Baz",
            "-emit-executable",
            "@\(buildPath.appending(components: "Foo.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])

        XCTAssertEqual(barLinkArgs, [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Bar-Baz.dll").pathString,
            "-module-name", "Bar_Baz",
            "-emit-library",
            "@\(buildPath.appending(components: "Bar-Baz.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #else
        XCTAssertEqual(fooLinkArgs, [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Foo").pathString,
            "-module-name", "Foo",
            "-lBar-Baz",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "Foo.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])

        XCTAssertEqual(barLinkArgs, [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "libBar-Baz.so").pathString,
            "-module-name", "Bar_Baz",
            "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "Bar-Baz.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
        ])
      #endif

      #if os(macOS)
        XCTAssert(
            barLinkArgs.contains("-install_name")
                && barLinkArgs.contains("@rpath/libBar-Baz.dylib")
                && barLinkArgs.contains("-rpath")
                && barLinkArgs.contains("@loader_path"),
            "The dynamic library will not work once moved outside the build directory."
        )
      #endif
    }

    func testExecAsDependency() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    products: [
                        ProductDescription(name: "lib", type: .library(.dynamic), targets: ["lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertMatch(lib, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

        #if os(macOS)
            let linkArguments = [
                result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "liblib.dylib").pathString,
                "-module-name", "lib",
                "-emit-library",
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/liblib.dylib",
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
                "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
                "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
                "-target", defaultTargetTriple,
                "-Xlinker", "-add_ast_path", "-Xlinker", buildPath.appending(components: "lib.swiftmodule").pathString,
            ]
        #elseif os(Windows)
            let linkArguments = [
                result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "lib.dll").pathString,
                "-module-name", "lib",
                "-emit-library",
                "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
                "-target", defaultTargetTriple,
            ]
        #else
            let linkArguments = [
                result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "liblib.so").pathString,
                "-module-name", "lib",
                "-emit-library",
                "-Xlinker", "-rpath=$ORIGIN",
                "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
                "-target", defaultTargetTriple,
            ]
        #endif

        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), linkArguments)
    }

    func testClangTargets() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.cpp").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    products: [
                        ProductDescription(name: "lib", type: .library(.dynamic), targets: ["lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(2)
        result.checkTargetsCount(2)
        
        let triple = result.plan.buildParameters.triple
        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let exe = try result.target(for: "exe").clangTarget()
        
        var expectedExeBasicArgs = triple.isDarwin() ? ["-fobjc-arc"] : []
        expectedExeBasicArgs += ["-target", defaultTargetTriple]
        expectedExeBasicArgs += ["-g"] + (triple.isWindows() ? ["-gcodeview"] : [])
        expectedExeBasicArgs += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks"]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        expectedExeBasicArgs += ["-fmodules", "-fmodule-name=exe"]
#endif
        expectedExeBasicArgs += ["-I", Pkg.appending(components: "Sources", "exe", "include").pathString]
#if !os(Windows)    // FIXME(5473) - modules flags on Windows dropped
        expectedExeBasicArgs += ["-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"]
#endif
        XCTAssertEqual(try exe.basicArguments(isCXX: false), expectedExeBasicArgs)
        XCTAssertEqual(try exe.objects, [buildPath.appending(components: "exe.build", "main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

        let lib = try result.target(for: "lib").clangTarget()
        
        var expectedLibBasicArgs = triple.isDarwin() ? ["-fobjc-arc"] : []
        expectedLibBasicArgs += ["-target", defaultTargetTriple]
        expectedLibBasicArgs += ["-g"] + (triple.isWindows() ? ["-gcodeview"] : [])
        expectedLibBasicArgs += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks"]
        let shouldHaveModules = !(triple.isDarwin() || triple.isWindows() || triple.isAndroid())
        if shouldHaveModules {
            expectedLibBasicArgs += ["-fmodules", "-fmodule-name=lib"]
        }
        expectedLibBasicArgs += ["-I", Pkg.appending(components: "Sources", "lib", "include").pathString]
        if shouldHaveModules {
            expectedLibBasicArgs += ["-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"]
        }
        XCTAssertEqual(try lib.basicArguments(isCXX: true), expectedLibBasicArgs)

        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.cpp.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

    #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-lc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "liblib.dylib").pathString,
            "-module-name", "lib",
            "-emit-library",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/liblib.dylib",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple
        ])
    #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "lib.dll").pathString,
            "-module-name", "lib",
            "-emit-library",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple
        ])
    #else
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-lstdc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "liblib.so").pathString,
            "-module-name", "lib",
            "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple
        ])
    #endif
    }

    func testNonReachableProductsAndTargets() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/B/Sources/BTarget1/BTarget1.swift",
            "/B/Sources/BTarget2/main.swift",
            "/C/Sources/CTarget/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/C"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "aexec", type: .executable, targets: ["ATarget"])
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: .init(path: "/B"),
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.static), targets: ["BTarget1"]),
                        ProductDescription(name: "bexec", type: .executable, targets: ["BTarget2"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget1", dependencies: []),
                        TargetDescription(name: "BTarget2", dependencies: []),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "C",
                    path: .init(path: "/C"),
                    products: [
                        ProductDescription(name: "cexec", type: .executable, targets: ["CTarget"])
                    ],
                    targets: [
                        TargetDescription(name: "CTarget", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        XCTAssertEqual(observability.diagnostics.count, 1)
        let firstDiagnostic = observability.diagnostics.first.map({ $0.message })
        XCTAssert(
            firstDiagnostic == "dependency 'c' is not used by any target",
            "Unexpected diagnostic: " + (firstDiagnostic ?? "[none]")
        )
        #endif

        let graphResult = PackageGraphResult(graph)
        graphResult.check(reachableProducts: "aexec", "BLibrary")
        graphResult.check(reachableTargets: "ATarget", "BTarget1")
        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        graphResult.check(products: "aexec", "BLibrary")
        graphResult.check(targets: "ATarget", "BTarget1")
        #else
        graphResult.check(products: "BLibrary", "bexec", "aexec", "cexec")
        graphResult.check(targets: "ATarget", "BTarget1", "BTarget2", "CTarget")
        #endif

        let planResult = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        planResult.checkProductsCount(2)
        planResult.checkTargetsCount(2)
        #else
        planResult.checkProductsCount(4)
        planResult.checkTargetsCount(4)
        #endif
    }

    func testReachableBuildProductsAndTargets() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/B/Sources/BTarget1/source.swift",
            "/B/Sources/BTarget2/source.swift",
            "/B/Sources/BTarget3/source.swift",
            "/C/Sources/CTarget/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: .init(path: "/C"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "aexec", type: .executable, targets: ["ATarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: [
                            .product(name: "BLibrary1", package: "B", condition: PackageConditionDescription(
                                platformNames: ["linux"],
                                config: nil
                            )),
                            .product(name: "BLibrary2", package: "B", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            )),
                            .product(name: "CLibrary", package: "C", condition: PackageConditionDescription(
                                platformNames: ["android"],
                                config: "release"
                            )),
                        ])
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "B",
                    path: .init(path: "/B"),
                    products: [
                        ProductDescription(name: "BLibrary1", type: .library(.static), targets: ["BTarget1"]),
                        ProductDescription(name: "BLibrary2", type: .library(.static), targets: ["BTarget2"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget1", dependencies: []),
                        TargetDescription(name: "BTarget2", dependencies: [
                            .target(name: "BTarget3", condition: PackageConditionDescription(
                                platformNames: ["macos"],
                                config: nil
                            )),
                        ]),
                        TargetDescription(name: "BTarget3", dependencies: []),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "C",
                    path: .init(path: "/C"),
                    products: [
                        ProductDescription(name: "CLibrary", type: .library(.static), targets: ["CTarget"])
                    ],
                    targets: [
                        TargetDescription(name: "CTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        let graphResult = PackageGraphResult(graph)

        do {
            let linuxDebug = BuildEnvironment(platform: .linux, configuration: .debug)
            try graphResult.check(reachableBuildProducts: "aexec", "BLibrary1", "BLibrary2", in: linuxDebug)
            try graphResult.check(reachableBuildTargets: "ATarget", "BTarget1", "BTarget2", in: linuxDebug)

            let planResult = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: linuxDebug),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }

        do {
            let macosDebug = BuildEnvironment(platform: .macOS, configuration: .debug)
            try graphResult.check(reachableBuildProducts: "aexec", "BLibrary2", in: macosDebug)
            try graphResult.check(reachableBuildTargets: "ATarget", "BTarget2", "BTarget3", in: macosDebug)

            let planResult = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: macosDebug),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }

        do {
            let androidRelease = BuildEnvironment(platform: .android, configuration: .release)
            try graphResult.check(reachableBuildProducts: "aexec", "CLibrary", in: androidRelease)
            try graphResult.check(reachableBuildTargets: "ATarget", "CTarget", in: androidRelease)

            let planResult = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(environment: androidRelease),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }
    }

    func testSystemPackageBuildPlan() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg")
                )
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        XCTAssertThrows(BuildPlan.Error.noBuildableTarget) {
            _ = try BuildPlan(
                buildParameters: mockBuildParameters(),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
        }
    }

    func testPkgConfigHintDiagnostic() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Sources/BTarget/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BTarget"]),
                        TargetDescription(
                            name: "BTarget",
                            type: .system,
                            pkgConfig: "BTarget",
                            providers: [
                                .brew(["BTarget"]),
                                .apt(["BTarget"]),
                                .yum(["BTarget"]),
                            ]
                        )
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        _ = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )

#if !os(Windows)    // FIXME: pkg-config is not generally available on Windows
        XCTAssertTrue(observability.diagnostics.contains(where: {
            $0.severity == .warning &&
            $0.message.hasPrefix("you may be able to install BTarget using your system-packager")
        }), "expected PkgConfigHint diagnostics")
#endif
    }

    func testPkgConfigGenericDiagnostic() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Sources/BTarget/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BTarget"]),
                        TargetDescription(
                            name: "BTarget",
                            type: .system,
                            pkgConfig: "BTarget"
                        )
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        _ = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )

        let diagnostic = observability.diagnostics.last!

        XCTAssertEqual(diagnostic.message, "couldn't find pc file for BTarget")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.metadata?.targetName, "BTarget")
        XCTAssertEqual(diagnostic.metadata?.pcFile, "BTarget.pc")
    }

    func testWindowsTarget() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")
        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    targets: [
                    TargetDescription(name: "exe", dependencies: ["lib"]),
                    TargetDescription(name: "lib", dependencies: []),
                ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: .windows),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let lib = try result.target(for: "lib").clangTarget()
        let args = [
            "-target", "x86_64-unknown-windows-msvc", "-g", "-gcodeview", "-O0",
            "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks", "-I", Pkg.appending(components: "Sources", "lib", "include").pathString
        ]
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.c.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g", .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG","-Xcc", "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))", "-Xcc", "-I", "-Xcc", "\(Pkg.appending(components: "Sources", "lib", "include"))", "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe", "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
             "-target", "x86_64-unknown-windows-msvc",
            ])

        let executablePathExtension = try result.buildProduct(for: "exe").binaryPath.extension
        XCTAssertMatch(executablePathExtension, "exe")
    }

    func testWASITarget() throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "app", "main.swift").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString,
            Pkg.appending(components: "Tests", "test", "TestCase.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    targets: [
                        TargetDescription(name: "app", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "test", dependencies: ["lib"], type: .test)
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        var parameters = mockBuildParameters(destinationTriple: .wasi)
        parameters.shouldLinkStaticSwiftStdlib = true
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(5) // There are two additional targets on non-Apple platforms, for test discovery and test entry point

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let lib = try result.target(for: "lib").clangTarget()
        let args = [
            "-target", "wasm32-unknown-wasi",
            "-g", "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1",
            "-fblocks", "-fmodules", "-fmodule-name=lib",
            "-I", Pkg.appending(components: "Sources", "lib", "include").pathString,
            "-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"
        ]
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.c.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        let exe = try result.target(for: "app").swiftTarget().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-swift-version", "4", "-enable-batch-mode", "-Onone", "-enable-testing", "-g",
                .equal(j), "-DSWIFT_PACKAGE", "-DDEBUG","-Xcc",
                "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))",
                "-Xcc", "-I", "-Xcc", "\(Pkg.appending(components: "Sources", "lib", "include"))",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence
            ]
        )

        let appBuildDescription = try result.buildProduct(for: "app")
        XCTAssertEqual(
            try appBuildDescription.linkArguments(),
            [
                result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "app.wasm").pathString,
                "-module-name", "app", "-static-stdlib", "-emit-executable",
                "@\(buildPath.appending(components: "app.product", "Objects.LinkFileList"))",
                "-target", "wasm32-unknown-wasi"
            ]
        )

        let executablePathExtension = appBuildDescription.binaryPath.extension
        XCTAssertEqual(executablePathExtension, "wasm")

        let testBuildDescription = try result.buildProduct(for: "PkgPackageTests")
        XCTAssertEqual(
            try testBuildDescription.linkArguments(),
            [
                result.plan.buildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "PkgPackageTests.wasm").pathString,
                "-module-name", "PkgPackageTests",
                "-emit-executable",
                "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
                "-target", "wasm32-unknown-wasi"
            ]
        )

        let testPathExtension = testBuildDescription.binaryPath.extension
        XCTAssertEqual(testPathExtension, "wasm")
    }

    func testEntrypointRenaming() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    toolsVersion: .v5_5,
                    targets: [
                        TargetDescription(name: "exe", type: .executable),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        func createResult(for triple: Basics.Triple) throws -> BuildPlanResult {
            try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(canRenameEntrypointFunctionName: true, destinationTriple: triple),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))
        }
        let supportingTriples: [Basics.Triple] = [.x86_64Linux, .macOS]
        for triple in supportingTriples {
            let result = try createResult(for: triple)
            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, ["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "exe_main"])
            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.contains("exe_main")])
        }

        let unsupportingTriples: [Basics.Triple] = [.wasi, .windows]
        for triple in unsupportingTriples {
            let result = try createResult(for: triple)
            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertNoMatch(exe, ["-entry-point-function-name"])
        }
    }

    func testIndexStore() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func check(for mode: BuildParameters.IndexStoreMode, config: BuildConfiguration) throws {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(config: config, indexStoreMode: mode),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let lib = try result.target(for: "lib").clangTarget()
            let path = StringPattern.equal(result.plan.buildParameters.indexStore.pathString)

            #if os(macOS)
            XCTAssertMatch(try lib.basicArguments(isCXX: false), [.anySequence, "-index-store-path", path, .anySequence])
            #else
            XCTAssertNoMatch(try lib.basicArguments(isCXX: false), [.anySequence, "-index-store-path", path, .anySequence])
            #endif

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-index-store-path", path, .anySequence])
        }

        try check(for: .auto, config: .debug)
        try check(for: .on, config: .debug)
        try check(for: .on, config: .release)
    }

    func testPlatforms() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: .init(path: "/B"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.12"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        let aTarget = try result.target(for: "ATarget").swiftTarget().compileArguments()
      #if os(macOS)
        XCTAssertMatch(aTarget, [.equal("-target"), .equal(hostTriple.tripleString(forPlatformVersion: "10.13")), .anySequence])
      #else
        XCTAssertMatch(aTarget, [.equal("-target"), .equal(defaultTargetTriple), .anySequence] )
      #endif

        let bTarget = try result.target(for: "BTarget").swiftTarget().compileArguments()
      #if os(macOS)
        XCTAssertMatch(bTarget, [.equal("-target"), .equal(hostTriple.tripleString(forPlatformVersion: "10.13")), .anySequence])
      #else
        XCTAssertMatch(bTarget, [.equal("-target"), .equal(defaultTargetTriple), .anySequence] )
      #endif
    }

    func testPlatformsValidation() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: .init(path: "/A"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                        PlatformDescription(name: "ios", version: "10"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: .init(path: "/B"),
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.14"),
                        PlatformDescription(name: "ios", version: "11"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        XCTAssertThrows(Diagnostics.fatalError) {
            _ = try BuildPlan(
                buildParameters: mockBuildParameters(destinationTriple: .macOS),
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            )
        }

        testDiagnostics(observability.diagnostics) { result in
            let diagnosticMessage = """
            the library 'ATarget' requires macos 10.13, but depends on the product 'BLibrary' which requires macos 10.14; \
            consider changing the library 'ATarget' to require macos 10.14 or later, or the product 'BLibrary' to require \
            macos 10.13 or earlier.
            """
            result.check(diagnostic: .contains(diagnosticMessage), severity: .error)
        }
    }

    func testBuildSettings() throws {
        let A = AbsolutePath("/A")

        let fs = InMemoryFileSystem(emptyFiles:
            "/A/Sources/exe/main.swift",
            "/A/Sources/bar/bar.swift",
            "/A/Sources/cbar/barcpp.cpp",
            "/A/Sources/cbar/bar.c",
            "/A/Sources/cbar/include/bar.h",

            "/B/Sources/t1/dep.swift",
            "/B/Sources/t2/dep.swift",
            "<end>"
        )

        let aManifest = Manifest.createRootManifest(
            displayName: "A",
            path: .init(path: "/A"),
            toolsVersion: .v5,
            dependencies: [
                .localSourceControl(path: .init(path: "/B"), requirement: .upToNextMajor(from: "1.0.0")),
            ],
            targets: [
                try TargetDescription(
                    name: "cbar",
                    settings: [
                        .init(tool: .c, kind: .headerSearchPath("Sources/headers")),
                        .init(tool: .cxx, kind: .headerSearchPath("Sources/cppheaders")),
                        .init(tool: .c, kind: .define("CCC=2")),
                        .init(tool: .cxx, kind: .define("RCXX"), condition: .init(config: "release")),
                        .init(tool: .linker, kind: .linkedFramework("best")),
                        .init(tool: .c, kind: .unsafeFlags(["-Icfoo", "-L", "cbar"])),
                        .init(tool: .cxx, kind: .unsafeFlags(["-Icxxfoo", "-L", "cxxbar"])),
                    ]
                ),
                try TargetDescription(
                    name: "bar", dependencies: ["cbar", "Dep"],
                    settings: [
                        .init(tool: .swift, kind: .define("LINUX"), condition: .init(platformNames: ["linux"])),
                        .init(tool: .swift, kind: .define("RLINUX"), condition: .init(platformNames: ["linux"], config: "release")),
                        .init(tool: .swift, kind: .define("DMACOS"), condition: .init(platformNames: ["macos"], config: "debug")),
                        .init(tool: .swift, kind: .unsafeFlags(["-Isfoo", "-L", "sbar"])),
                        .init(tool: .swift, kind: .interoperabilityMode(.Cxx, "swift-5.9"), condition: .init(platformNames: ["linux"])),
                        .init(tool: .swift, kind: .interoperabilityMode(.Cxx, "swift-6.0"), condition: .init(platformNames: ["macos"])),
                        .init(tool: .swift, kind: .enableUpcomingFeature("BestFeature")),
                        .init(tool: .swift, kind: .enableUpcomingFeature("WorstFeature"), condition: .init(platformNames: ["macos"], config: "debug"))
                    ]
                ),
                try TargetDescription(
                    name: "exe", dependencies: ["bar"],
                    settings: [
                        .init(tool: .swift, kind: .define("FOO")),
                        .init(tool: .swift, kind: .interoperabilityMode(.C, nil)),
                        .init(tool: .linker, kind: .linkedLibrary("sqlite3")),
                        .init(tool: .linker, kind: .linkedFramework("CoreData"), condition: .init(platformNames: ["macos"])),
                        .init(tool: .linker, kind: .unsafeFlags(["-Ilfoo", "-L", "lbar"])),
                    ]
                ),
            ]
        )

        let bManifest = Manifest.createFileSystemManifest(
            displayName: "B",
            path: .init(path: "/B"),
            toolsVersion: .v5,
            products: [
                try ProductDescription(name: "Dep", type: .library(.automatic), targets: ["t1", "t2"]),
            ],
            targets: [
                try TargetDescription(
                    name: "t1",
                    settings: [
                        .init(tool: .swift, kind: .define("DEP")),
                        .init(tool: .linker, kind: .linkedLibrary("libz")),
                    ]
                ),
                try TargetDescription(
                    name: "t2",
                    settings: [
                        .init(tool: .linker, kind: .linkedLibrary("libz")),
                    ]
                ),
            ])

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [aManifest, bManifest],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func createResult(for dest: Basics.Triple) throws -> BuildPlanResult {
            return try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(destinationTriple: dest),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))
        }

        do {
            let result = try createResult(for: .x86_64Linux)

            let dep = try result.target(for: "t1").swiftTarget().compileArguments()
            XCTAssertMatch(dep, [.anySequence, "-DDEP", .end])

            let cbar = try result.target(for: "cbar").clangTarget().basicArguments(isCXX: false)
            XCTAssertMatch(cbar, [.anySequence, "-DCCC=2", "-I\(A.appending(components: "Sources", "cbar", "Sources", "headers"))", "-I\(A.appending(components: "Sources", "cbar", "Sources", "cppheaders"))", "-Icfoo", "-L", "cbar", "-Icxxfoo", "-L", "cxxbar", .end])

            let bar = try result.target(for: "bar").swiftTarget().compileArguments()
            XCTAssertMatch(bar, [.anySequence, "-DLINUX", "-Isfoo", "-L", "sbar", "-cxx-interoperability-mode=swift-5.9", "-enable-upcoming-feature", "BestFeature", .end])

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-DFOO", .end])

            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.anySequence, "-lsqlite3", "-llibz", "-framework", "best", "-Ilfoo", "-L", "lbar", .end])
        }

        do {
            let result = try createResult(for: .macOS)

            let cbar = try result.target(for: "cbar").clangTarget().basicArguments(isCXX: false)
            XCTAssertMatch(cbar, [.anySequence, "-DCCC=2", "-I\(A.appending(components: "Sources", "cbar", "Sources", "headers"))", "-I\(A.appending(components: "Sources", "cbar", "Sources", "cppheaders"))", "-Icfoo", "-L", "cbar", "-Icxxfoo", "-L", "cxxbar", .end])

            let bar = try result.target(for: "bar").swiftTarget().compileArguments()
            XCTAssertMatch(bar, [.anySequence, "-DDMACOS", "-Isfoo", "-L", "sbar", "-cxx-interoperability-mode=swift-6.0", "-enable-upcoming-feature", "BestFeature", "-enable-upcoming-feature", "WorstFeature", .end])

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-DFOO", .end])

            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.anySequence, "-lsqlite3", "-llibz", "-framework", "CoreData", "-framework", "best", "-Ilfoo", "-L", "lbar", .anySequence])
        }
    }

    func testExtraBuildFlags() throws {
        let libpath = AbsolutePath("/fake/path/lib")

        let fs = InMemoryFileSystem(emptyFiles:
            "/A/Sources/exe/main.swift",
            libpath.appending(components: "libSomething.dylib").pathString,
            "<end>"
        )

        let aManifest = Manifest.createRootManifest(
            displayName: "A",
            path: .init(path: "/A"),
            toolsVersion: .v5,
            targets: [
                try TargetDescription(name: "exe", dependencies: []),
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [aManifest],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        var flags = BuildFlags()
        flags.linkerFlags = ["-L", "/path/to/foo", "-L/path/to/foo", "-rpath=foo", "-rpath", "foo"]
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(flags: flags),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let exe = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(exe, [.anySequence, "-L", "/path/to/foo", "-L/path/to/foo", "-Xlinker", "-rpath=foo", "-Xlinker", "-rpath", "-Xlinker", "foo", "-L", "\(libpath)"])
    }

    func testUserToolchainCompileFlags() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let userDestination = Destination(
            toolset: .init(
                knownTools: [
                    .cCompiler: .init(extraCLIOptions: ["-I/fake/sdk/sysroot", "-clang-flag-from-json"]),
                    .swiftCompiler: .init(extraCLIOptions: ["-swift-flag-from-json"])
                ],
                rootPaths: try UserToolchain.default.destination.toolset.rootPaths
            ),
            pathsConfiguration: .init(sdkRootPath: "/fake/sdk")
        )
        let mockToolchain = try UserToolchain(destination: userDestination)
        let extraBuildParameters = mockBuildParameters(toolchain: mockToolchain,
            flags: BuildFlags(cCompilerFlags: ["-clang-command-line-flag"], swiftCompilerFlags: ["-swift-command-line-flag"]))
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: extraBuildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let lib = try result.target(for: "lib").clangTarget()
        var args: [StringPattern] = [.anySequence]
      #if os(macOS)
        args += ["-isysroot"]
      #else
        args += ["--sysroot"]
      #endif
        args += ["\(userDestination.pathsConfiguration.sdkRootPath!)", "-I/fake/sdk/sysroot", "-clang-flag-from-json", .anySequence, "-clang-command-line-flag"]
        XCTAssertMatch(try lib.basicArguments(isCXX: false), args)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence, "-swift-flag-from-json", "-Xcc", "-clang-command-line-flag", "-swift-command-line-flag"])
    }

    func testExecBuildTimeDependency() throws {
        let PkgA = AbsolutePath("/PkgA")

        let fs = InMemoryFileSystem(emptyFiles:
            PkgA.appending(components: "Sources", "exe", "main.swift").pathString,
            PkgA.appending(components: "Sources", "swiftlib", "lib.swift").pathString,
            "/PkgB/Sources/PkgB/PkgB.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "PkgA",
                    path: try .init(validating: PkgA.pathString),
                    products: [
                        ProductDescription(name: "swiftlib", type: .library(.automatic), targets: ["swiftlib"]),
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"])
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                        TargetDescription(name: "swiftlib", dependencies: ["exe"]),
                    ]),
                Manifest.createRootManifest(
                    displayName: "PkgB",
                    path: .init(path: "/PkgB"),
                    dependencies: [
                        .localSourceControl(path: try .init(validating: PkgA.pathString), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "PkgB", dependencies: ["swiftlib"]),
                    ]),
            ],
            explicitProduct: "exe",
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let buildPath: AbsolutePath = plan.buildParameters.dataPath.appending(components: "debug")

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
#if os(Windows)
        XCTAssertMatch(contents, .contains("""
                inputs: ["\(PkgA.appending(components: "Sources", "swiftlib", "lib.swift").escapedPathString())","\(buildPath.appending(components: "exe.exe").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "swiftlib.build", "lib.swift.o").escapedPathString())","\(buildPath.escapedPathString())
            """))
#else   // FIXME(5472) - the suffix is dropped
        XCTAssertMatch(contents, .contains("""
                inputs: ["\(PkgA.appending(components: "Sources", "swiftlib", "lib.swift").escapedPathString())","\(buildPath.appending(components: "exe").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "swiftlib.build", "lib.swift.o").escapedPathString())","\(buildPath.escapedPathString())
            """))
#endif
    }

    func testObjCHeader1() throws {
        let PkgA = AbsolutePath("/PkgA")

        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(emptyFiles:
            PkgA.appending(components: "Sources", "Bar", "main.m").pathString,
            PkgA.appending(components: "Sources", "Foo", "Foo.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: try .init(validating: PkgA.pathString),
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let fooTarget = try result.target(for: "Foo").swiftTarget().compileArguments()
        #if os(macOS)
          XCTAssertMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
        #else
          XCTAssertNoMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
        #endif

        let barTarget = try result.target(for: "Bar").clangTarget().basicArguments(isCXX: false)
        #if os(macOS)
          XCTAssertMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
        #else
          XCTAssertNoMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
        #endif

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
              "\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString())":
                tool: clang
                inputs: ["\(buildPath.appending(components: "Foo.swiftmodule").escapedPathString())","\(PkgA.appending(components: "Sources", "Bar", "main.m").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString())"]
                description: "Compiling Bar main.m"
            """))
    }

    func testObjCHeader2() throws {
        let PkgA = AbsolutePath("/PkgA")

        // This has a Swift and ObjC target in different packages with automatic product type.
        let fs = InMemoryFileSystem(emptyFiles:
            PkgA.appending(components: "Sources", "Bar", "main.m").pathString,
            "/PkgB/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: try .init(validating: PkgA.pathString),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/PkgB"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "PkgB",
                    path: .init(path: "/PkgB"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

         let fooTarget = try result.target(for: "Foo").swiftTarget().compileArguments()
         #if os(macOS)
           XCTAssertMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #else
           XCTAssertNoMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #endif

         let barTarget = try result.target(for: "Bar").clangTarget().basicArguments(isCXX: false)
         #if os(macOS)
           XCTAssertMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #else
           XCTAssertNoMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #endif

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
               "\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString())":
                 tool: clang
                 inputs: ["\(buildPath.appending(components: "Foo.swiftmodule").escapedPathString())","\(PkgA.appending(components: "Sources", "Bar", "main.m").escapedPathString())"]
                 outputs: ["\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString())"]
                 description: "Compiling Bar main.m"
             """))
    }

    func testObjCHeader3() throws {
        let PkgA = AbsolutePath("/PkgA")

        // This has a Swift and ObjC target in different packages with dynamic product type.
        let fs = InMemoryFileSystem(emptyFiles:
            PkgA.appending(components: "Sources", "Bar", "main.m").pathString,
            "/PkgB/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: try .init(validating: PkgA.pathString),
                    dependencies: [
                        .localSourceControl(path: .init(path: "/PkgB"), requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]),
                Manifest.createFileSystemManifest(
                    displayName: "PkgB",
                    path: .init(path: "/PkgB"),
                    products: [
                        ProductDescription(name: "Foo", type: .library(.dynamic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let dynamicLibraryExtension = plan.buildParameters.triple.dynamicLibraryExtension
#if os(Windows)
        let dynamicLibraryPrefix = ""
#else
        let dynamicLibraryPrefix = "lib"
#endif
        let result = try BuildPlanResult(plan: plan)

         let fooTarget = try result.target(for: "Foo").swiftTarget().compileArguments()
         #if os(macOS)
           XCTAssertMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #else
           XCTAssertNoMatch(fooTarget, [.anySequence, "-emit-objc-header", "-emit-objc-header-path", "/path/to/build/debug/Foo.build/Foo-Swift.h", .anySequence])
         #endif

         let barTarget = try result.target(for: "Bar").clangTarget().basicArguments(isCXX: false)
         #if os(macOS)
           XCTAssertMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #else
           XCTAssertNoMatch(barTarget, [.anySequence, "-fmodule-map-file=/path/to/build/debug/Foo.build/module.modulemap", .anySequence])
         #endif

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
               "\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString())":
                 tool: clang
                 inputs: ["\(buildPath.appending(components: "\(dynamicLibraryPrefix)Foo\(dynamicLibraryExtension)").escapedPathString())","\(PkgA.appending(components: "Sources", "Bar", "main.m").escapedPathString())"]
                 outputs: ["\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString())"]
                 description: "Compiling Bar main.m"
             """))
    }

    func testModulewrap() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: .x86_64Linux),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let objects = try result.buildProduct(for: "exe").objects
        XCTAssertTrue(objects.contains(buildPath.appending(components: "exe.build", "exe.swiftmodule.o")), objects.description)
        XCTAssertTrue(objects.contains(buildPath.appending(components: "lib.build", "lib.swiftmodule.o")), objects.description)

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(result.plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
              "\(buildPath.appending(components: "exe.build", "exe.swiftmodule.o").escapedPathString())":
                tool: shell
                inputs: ["\(buildPath.appending(components: "exe.build", "exe.swiftmodule").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "exe.build", "exe.swiftmodule.o").escapedPathString())"]
                description: "Wrapping AST for exe for debugging"
                args: ["\(result.plan.buildParameters.toolchain.swiftCompilerPath.escapedPathString())","-modulewrap","\(buildPath.appending(components: "exe.build", "exe.swiftmodule").escapedPathString())","-o","\(buildPath.appending(components: "exe.build", "exe.swiftmodule.o").escapedPathString())","-target","x86_64-unknown-linux-gnu"]
            """))
        XCTAssertMatch(contents, .contains("""
              "\(buildPath.appending(components: "lib.build", "lib.swiftmodule.o").escapedPathString())":
                tool: shell
                inputs: ["\(buildPath.appending(components: "lib.swiftmodule").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "lib.build", "lib.swiftmodule.o").escapedPathString())"]
                description: "Wrapping AST for lib for debugging"
                args: ["\(result.plan.buildParameters.toolchain.swiftCompilerPath.escapedPathString())","-modulewrap","\(buildPath.appending(components: "lib.swiftmodule").escapedPathString())","-o","\(buildPath.appending(components: "lib.build", "lib.swiftmodule.o").escapedPathString())","-target","x86_64-unknown-linux-gnu"]
            """))
    }

    func testArchiving() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Package/Sources/rary/rary.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Package",
                    path: .init(path: "/Package"),
                    products: [
                        ProductDescription(name: "rary", type: .library(.static), targets: ["rary"]),
                    ],
                    targets: [
                        TargetDescription(name: "rary", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)

        let llbuild = LLBuildManifestBuilder(result.plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)

        let contents: String = try fs.readFileContents(yaml)

        if result.plan.buildParameters.triple.isWindows() {
            XCTAssertMatch(contents, .contains("""
              "C.rary-debug.a":
                tool: shell
                inputs: ["\(buildPath.appending(components: "rary.build", "rary.swift.o").escapedPathString())","\(buildPath.appending(components: "rary.build", "rary.swiftmodule.o").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "library.a").escapedPathString())"]
                description: "Archiving \(buildPath.appending(components: "library.a").escapedPathString())"
                args: ["\(result.plan.buildParameters.toolchain.librarianPath.escapedPathString())","/LIB","/OUT:\(buildPath.appending(components: "library.a").escapedPathString())","@\(buildPath.appending(components: "rary.product", "Objects.LinkFileList").escapedPathString())"]
            """))
        } else if result.plan.buildParameters.triple.isDarwin() {
            XCTAssertMatch(contents, .contains("""
              "C.rary-debug.a":
                tool: shell
                inputs: ["\(buildPath.appending(components: "rary.build", "rary.swift.o").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "library.a").escapedPathString())"]
                description: "Archiving \(buildPath.appending(components: "library.a").escapedPathString())"
                args: ["\(result.plan.buildParameters.toolchain.librarianPath.escapedPathString())","-static","-o","\(buildPath.appending(components: "library.a").escapedPathString())","@\(buildPath.appending(components: "rary.product", "Objects.LinkFileList").escapedPathString())"]
            """))
        } else {    // assume Unix `ar` is the librarian
            XCTAssertMatch(contents, .contains("""
              "C.rary-debug.a":
                tool: shell
                inputs: ["\(buildPath.appending(components: "rary.build", "rary.swift.o").escapedPathString())","\(buildPath.appending(components: "rary.build", "rary.swiftmodule.o").escapedPathString())"]
                outputs: ["\(buildPath.appending(components: "library.a").escapedPathString())"]
                description: "Archiving \(buildPath.appending(components: "library.a").escapedPathString())"
                args: ["\(result.plan.buildParameters.toolchain.librarianPath.escapedPathString())","crs","\(buildPath.appending(components: "library.a").escapedPathString())","@\(buildPath.appending(components: "rary.product", "Objects.LinkFileList").escapedPathString())"]
            """))
        }
    }

    func testSwiftBundleAccessor() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Foo/Foo.swift",
            "/PkgA/Sources/Foo/foo.txt",
            "/PkgA/Sources/Foo/bar.txt",
            "/PkgA/Sources/Bar/Bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: .init(path: "/PkgA"),
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            resources: [
                                .init(rule: .copy, path: "foo.txt"),
                                .init(rule: .process(localization: .none), path: "bar.txt"),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar"
                        ),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let fooTarget = try result.target(for: "Foo").swiftTarget()
        XCTAssertEqual(try fooTarget.objects.map{ $0.pathString }, [
            buildPath.appending(components: "Foo.build", "Foo.swift.o").pathString,
            buildPath.appending(components: "Foo.build", "resource_bundle_accessor.swift.o").pathString,
        ])

        let resourceAccessor = fooTarget.sources.first{ $0.basename == "resource_bundle_accessor.swift" }!
        let contents: String = try fs.readFileContents(resourceAccessor)
        XCTAssertMatch(contents, .contains("extension Foundation.Bundle"))
        // Assert that `Bundle.main` is executed in the compiled binary (and not during compilation)
        // See https://bugs.swift.org/browse/SR-14555 and https://github.com/apple/swift-package-manager/pull/2972/files#r623861646
        XCTAssertMatch(contents, .contains("let mainPath = Bundle.main."))

        let barTarget = try result.target(for: "Bar").swiftTarget()
        XCTAssertEqual(try barTarget.objects.map{ $0.pathString }, [
            buildPath.appending(components: "Bar.build", "Bar.swift.o").pathString,
        ])
    }

    func testSwiftWASIBundleAccessor() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(emptyFiles:
            "/PkgA/Sources/Foo/Foo.swift",
            "/PkgA/Sources/Foo/foo.txt",
            "/PkgA/Sources/Foo/bar.txt",
            "/PkgA/Sources/Bar/Bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: .init(path: "/PkgA"),
                    toolsVersion: .v5_2,
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            resources: [
                                .init(rule: .copy, path: "foo.txt"),
                                .init(rule: .process(localization: .none), path: "bar.txt"),
                            ]
                        ),
                        TargetDescription(
                            name: "Bar"
                        ),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: .wasi),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let fooTarget = try result.target(for: "Foo").swiftTarget()
        XCTAssertEqual(try fooTarget.objects.map{ $0.pathString }, [
            buildPath.appending(components: "Foo.build", "Foo.swift.o").pathString,
            buildPath.appending(components: "Foo.build", "resource_bundle_accessor.swift.o").pathString
        ])

        let resourceAccessor = fooTarget.sources.first{ $0.basename == "resource_bundle_accessor.swift" }!
        let contents: String = try fs.readFileContents(resourceAccessor)
        XCTAssertMatch(contents, .contains("extension Foundation.Bundle"))
        // Assert that `Bundle.main` is executed in the compiled binary (and not during compilation)
        // See https://bugs.swift.org/browse/SR-14555 and https://github.com/apple/swift-package-manager/pull/2972/files#r623861646
        XCTAssertMatch(contents, .contains("let mainPath = \""))

        let barTarget = try result.target(for: "Bar").swiftTarget()
        XCTAssertEqual(try barTarget.objects.map{ $0.pathString }, [
            buildPath.appending(components: "Bar.build", "Bar.swift.o").pathString,
        ])
    }

    func testClangBundleAccessor() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/Foo/include/Foo.h",
            "/Pkg/Sources/Foo/Foo.m",
            "/Pkg/Sources/Foo/bar.h",
            "/Pkg/Sources/Foo/bar.c",
            "/Pkg/Sources/Foo/resource.txt"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    toolsVersion: .current,
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            resources: [
                                .init(
                                    rule: .process(localization: .none),
                                    path: "resource.txt"
                                )
                            ]
                        )
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending("debug")

        let fooTarget = try result.target(for: "Foo").clangTarget()
        XCTAssertEqual(try fooTarget.objects.map(\.pathString).sorted(), [
            buildPath.appending(components: "Foo.build", "Foo.m.o").pathString,
            buildPath.appending(components: "Foo.build", "bar.c.o").pathString,
            buildPath.appending(components: "Foo.build", "resource_bundle_accessor.m.o").pathString
        ].sorted())

        let resourceAccessorDirectory = buildPath.appending(components:
            "Foo.build",
            "DerivedSources"
        )

        let resourceAccessorHeader = resourceAccessorDirectory
            .appending("resource_bundle_accessor.h")
        let headerContents: String = try fs.readFileContents(resourceAccessorHeader)
        XCTAssertMatch(
            headerContents,
            .contains("#define SWIFTPM_MODULE_BUNDLE Foo_SWIFTPM_MODULE_BUNDLE()")
        )

        let resourceAccessorImpl = resourceAccessorDirectory
            .appending("resource_bundle_accessor.m")
        let implContents: String = try fs.readFileContents(resourceAccessorImpl)
        XCTAssertMatch(
            implContents,
            .contains("NSBundle* Foo_SWIFTPM_MODULE_BUNDLE() {")
        )
    }

    func testShouldLinkStaticSwiftStdlib() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )

        let supportingTriples: [Basics.Triple] = [.x86_64Linux, .arm64Linux, .wasi]
        for triple in supportingTriples {
            let result = try BuildPlanResult(plan: BuildPlan(
                buildParameters: mockBuildParameters(shouldLinkStaticSwiftStdlib: true, destinationTriple: triple),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let exe = try result.target(for: "exe").swiftTarget().compileArguments()
            XCTAssertMatch(exe, ["-static-stdlib"])
            let lib = try result.target(for: "lib").swiftTarget().compileArguments()
            XCTAssertMatch(lib, ["-static-stdlib"])
            let link = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(link, ["-static-stdlib"])
        }
    }

    func testXCFrameworkBinaryTargets(platform: String, arch: String, destinationTriple: Basics.Triple) throws {
        let Pkg: AbsolutePath = AbsolutePath("/Pkg")

        let fs = InMemoryFileSystem(emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "Library", "Library.swift").pathString,
            Pkg.appending(components: "Sources", "CLibrary", "library.c").pathString,
            Pkg.appending(components: "Sources", "CLibrary", "include", "library.h").pathString
        )

        try! fs.createDirectory("/Pkg/Framework.xcframework", recursive: true)
        try! fs.writeFileContents(
            "/Pkg/Framework.xcframework/Info.plist",
            bytes: ByteString(encodingAsUTF8: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>AvailableLibraries</key>
                    <array>
                        <dict>
                            <key>LibraryIdentifier</key>
                            <string>\(platform)-\(arch)</string>
                            <key>LibraryPath</key>
                            <string>Framework.framework</string>
                            <key>SupportedArchitectures</key>
                            <array>
                                <string>\(arch)</string>
                            </array>
                            <key>SupportedPlatform</key>
                            <string>\(platform)</string>
                        </dict>
                    </array>
                    <key>CFBundlePackageType</key>
                    <string>XFWK</string>
                    <key>XCFrameworkFormatVersion</key>
                    <string>1.0</string>
                </dict>
                </plist>
                """))

        try! fs.createDirectory("/Pkg/StaticLibrary.xcframework", recursive: true)
        try! fs.writeFileContents(
            "/Pkg/StaticLibrary.xcframework/Info.plist",
            bytes: ByteString(encodingAsUTF8: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                    <key>AvailableLibraries</key>
                    <array>
                        <dict>
                            <key>LibraryIdentifier</key>
                            <string>\(platform)-\(arch)</string>
                            <key>HeadersPath</key>
                            <string>Headers</string>
                            <key>LibraryPath</key>
                            <string>libStaticLibrary.a</string>
                            <key>SupportedArchitectures</key>
                            <array>
                                <string>\(arch)</string>
                            </array>
                            <key>SupportedPlatform</key>
                            <string>\(platform)</string>
                        </dict>
                    </array>
                    <key>CFBundlePackageType</key>
                    <string>XFWK</string>
                    <key>XCFrameworkFormatVersion</key>
                    <string>1.0</string>
                </dict>
                </plist>
                """))

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: Pkg.pathString),
                    products: [
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"]),
                        ProductDescription(name: "Library", type: .library(.dynamic), targets: ["Library"]),
                        ProductDescription(name: "CLibrary", type: .library(.dynamic), targets: ["CLibrary"]),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["Library"]),
                        TargetDescription(name: "Library", dependencies: ["Framework"]),
                        TargetDescription(name: "CLibrary", dependencies: ["StaticLibrary"]),
                        TargetDescription(name: "Framework", path: "Framework.xcframework", type: .binary),
                        TargetDescription(name: "StaticLibrary", path: "StaticLibrary.xcframework", type: .binary),
                    ]
                ),
            ],
            binaryArtifacts: [
                .plain("pkg"): [
                    "Framework": .init(kind: .xcframework, originURL: nil, path: "/Pkg/Framework.xcframework"),
                    "StaticLibrary": .init(kind: .xcframework, originURL: nil, path: "/Pkg/StaticLibrary.xcframework")
                ]
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: destinationTriple),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        XCTAssertNoDiagnostics(observability.diagnostics)

        result.checkProductsCount(3)
        result.checkTargetsCount(3)

        let buildPath: AbsolutePath = result.plan.buildParameters.dataPath.appending(components: "debug")

        let libraryBasicArguments = try result.target(for: "Library").swiftTarget().compileArguments()
        XCTAssertMatch(libraryBasicArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])

        let libraryLinkArguments = try result.buildProduct(for: "Library").linkArguments()
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-L", "\(buildPath)", .anySequence])
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-framework", "Framework", .anySequence])

        let exeCompileArguments = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exeCompileArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(exeCompileArguments, [.anySequence, "-I", "\(Pkg.appending(components: "Framework.xcframework", "\(platform)-\(arch)"))", .anySequence])

        let exeLinkArguments = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-L", "\(buildPath)", .anySequence])
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-framework", "Framework", .anySequence])

        let clibraryBasicArguments = try result.target(for: "CLibrary").clangTarget().basicArguments(isCXX: false)
        XCTAssertMatch(clibraryBasicArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(clibraryBasicArguments, [.anySequence, "-I", "\(Pkg.appending(components: "StaticLibrary.xcframework", "\(platform)-\(arch)", "Headers"))", .anySequence])

        let clibraryLinkArguments = try result.buildProduct(for: "CLibrary").linkArguments()
        XCTAssertMatch(clibraryLinkArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(clibraryLinkArguments, [.anySequence, "-L", "\(buildPath)", .anySequence])
        XCTAssertMatch(clibraryLinkArguments, ["-lStaticLibrary"])

        let executablePathExtension = try result.buildProduct(for: "exe").binaryPath.extension ?? ""
        XCTAssertMatch(executablePathExtension, "")

        let dynamicLibraryPathExtension = try result.buildProduct(for: "Library").binaryPath.extension
        XCTAssertMatch(dynamicLibraryPathExtension, "dylib")
    }

    func testXCFrameworkBinaryTargets() throws {
        try testXCFrameworkBinaryTargets(platform: "macos", arch: "x86_64", destinationTriple: .macOS)

        let arm64Triple = try Basics.Triple("arm64-apple-macosx")
        try testXCFrameworkBinaryTargets(platform: "macos", arch: "arm64", destinationTriple: arm64Triple)

        let arm64eTriple = try Basics.Triple("arm64e-apple-macosx")
        try testXCFrameworkBinaryTargets(platform: "macos", arch: "arm64e", destinationTriple: arm64eTriple)
    }

    func testArtifactsArchiveBinaryTargets(artifactTriples:[Basics.Triple], destinationTriple: Basics.Triple) throws -> Bool {
        let fs = InMemoryFileSystem(emptyFiles: "/Pkg/Sources/exe/main.swift")

        let artifactName = "my-tool"
        let toolPath = AbsolutePath("/Pkg/MyTool.artifactbundle")
        try fs.createDirectory(toolPath, recursive: true)

        try fs.writeFileContents(
            toolPath.appending("info.json"),
            bytes: ByteString(encodingAsUTF8: """
                {
                    "schemaVersion": "1.0",
                    "artifacts": {
                        "\(artifactName)": {
                            "type": "executable",
                            "version": "1.1.0",
                            "variants": [
                                {
                                    "path": "all-platforms/mytool",
                                    "supportedTriples": ["\(artifactTriples.map{ $0.tripleString }.joined(separator: "\", \""))"]
                                }
                            ]
                        }
                    }
                }
        """))

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    products: [
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"]),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["MyTool"]),
                        TargetDescription(name: "MyTool", path: "MyTool.artifactbundle", type: .binary),
                    ]
                ),
            ],
            binaryArtifacts: [
                .plain("pkg"): [
                    "MyTool": .init(kind: .artifactsArchive, originURL: nil, path: toolPath),
                ]
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: mockBuildParameters(destinationTriple: destinationTriple),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        XCTAssertNoDiagnostics(observability.diagnostics)

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let availableTools = try result.buildProduct(for: "exe").availableTools
        return availableTools.contains(where: { $0.key == artifactName })
    }

    func testArtifactsArchiveBinaryTargets() throws {
        XCTAssertTrue(try testArtifactsArchiveBinaryTargets(artifactTriples: [.macOS], destinationTriple: .macOS))

        do {
            let triples = try ["arm64-apple-macosx",  "x86_64-apple-macosx", "x86_64-unknown-linux-gnu"].map(Basics.Triple.init)
            XCTAssertTrue(try testArtifactsArchiveBinaryTargets(artifactTriples: triples, destinationTriple: triples.first!))
        }

        do {
            let triples = try ["x86_64-unknown-linux-gnu"].map(Basics.Triple.init)
            XCTAssertFalse(try testArtifactsArchiveBinaryTargets(artifactTriples: triples, destinationTriple: .macOS))
        }
    }

    func testAddressSanitizer() throws {
        try sanitizerTest(.address, expectedName: "address")
    }

    func testThreadSanitizer() throws {
        try sanitizerTest(.thread, expectedName: "thread")
    }

    func testUndefinedSanitizer() throws {
        try sanitizerTest(.undefined, expectedName: "undefined")
    }

    func testScudoSanitizer() throws {
        try sanitizerTest(.scudo, expectedName: "scudo")
    }

    func testSnippets() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/Lib/Lib.swift",
            "/Pkg/Snippets/ASnippet.swift",
            "/Pkg/.build/release.yaml"
        )
        let buildPath = AbsolutePath("/Pkg/.build")
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Lib",
                    path: .init(path: "/Pkg"),
                    toolsVersion: .vNext,
                    dependencies: [],
                    products: [
                        ProductDescription(name: "Lib", type: .library(.automatic), targets: ["Lib"])
                    ],
                    targets: [
                        TargetDescription(name: "Lib", dependencies: [], type: .regular),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let plan = try BuildPlan(
            buildParameters: mockBuildParameters(buildPath: buildPath),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let result = try BuildPlanResult(plan: plan)
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "ASnippet" && $0.target.type == .snippet })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "Lib" })

        let yaml = buildPath.appending("release.yaml")
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)

        let yamlContents: String = try fs.readFileContents(yaml)
        print(yamlContents)
        XCTAssertMatch(yamlContents, .contains("""
            inputs: ["/Pkg/Snippets/ASnippet.swift","/Pkg/.build/debug/Lib.swiftmodule"
        """))

    }

    private func sanitizerTest(_ sanitizer: PackageModel.Sanitizer, expectedName: String) throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Sources/clib/clib.c",
            "/Pkg/Sources/clib/include/clib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(path: "/Pkg"),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib", "clib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "clib", dependencies: []),
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        // Unrealistic: we can't enable all of these at once on all platforms.
        // This test codifies current behavior, not ideal behavior, and
        // may need to be amended if we change it.
        var parameters = mockBuildParameters(shouldLinkStaticSwiftStdlib: true)
        parameters.sanitizers = EnabledSanitizers([sanitizer])

        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let exe = try result.target(for: "exe").swiftTarget().compileArguments()
        XCTAssertMatch(exe, ["-sanitize=\(expectedName)"])

        let lib = try result.target(for: "lib").swiftTarget().compileArguments()
        XCTAssertMatch(lib, ["-sanitize=\(expectedName)"])

        let clib  = try result.target(for: "clib").clangTarget().basicArguments(isCXX: false)
        XCTAssertMatch(clib, ["-fsanitize=\(expectedName)"])

        XCTAssertMatch(try result.buildProduct(for: "exe").linkArguments(), ["-sanitize=\(expectedName)"])
    }
}
