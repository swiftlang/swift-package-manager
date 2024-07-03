//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
@testable import Build

@testable
@_spi(SwiftPMInternal)
import DriverSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph

import PackageLoading

@_spi(SwiftPMInternal)
@testable import PackageModel

import SPMBuildCore
import _InternalTestSupport
import SwiftDriver
import Workspace
import XCTest

import struct TSCBasic.ByteString

import enum TSCUtility.Diagnostics

extension Build.BuildPlan {
    var productsBuildPath: AbsolutePath {
        let buildParameters = self.destinationBuildParameters
        let buildConfigurationComponent = buildParameters.buildEnvironment
            .configuration == .release ? "release" : "debug"
        return buildParameters.dataPath.appending(components: buildConfigurationComponent)
    }
}

final class BuildPlanTests: XCTestCase {
    let inputsDir = AbsolutePath(#file).parentDirectory.appending(components: "Inputs")

    /// The j argument.
    private var j: String {
        "-j3"
    }

    func testDuplicateProductNamesWithNonDefaultLibsThrowError() throws {
        let fs = InMemoryFileSystem(
            emptyFiles: "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let fooPkg: AbsolutePath = "/fooPkg"
        let barPkg: AbsolutePath = "/barPkg"
        XCTAssertThrowsError(try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: fooPkg,
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: barPkg,
                    products: [
                        ProductDescription(name: "Logging", type: .library(.static), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: fooPkg, requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: barPkg, requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(name: "Logging", package: "fooPkg"),
                                           .product(name: "Logging", package: "barPkg")],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )) { error in
            XCTAssertEqual(
                (error as? PackageGraphError)?.description,
                "multiple packages (\'barpkg\' (at '\(barPkg)'), \'foopkg\' (at '\(fooPkg)')) declare products with a conflicting name: \'Logging’; product names need to be unique across the package graph"
            )
        }
    }

    func testDuplicateProductNamesWithADylib() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: "/fooPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.dynamic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: "/barPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(
                                name: "Logging",
                                package: "fooPkg"
                            ),
                            .product(
                                name: "Logging",
                                package: "barPkg"
                            )],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }

    func testDuplicateProductNamesUpstream1() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift",
            "/bazPkg/Sources/BazLogging/file.swift",
            "/xPkg/Sources/XUtils/file.swift",
            "/yPkg/Sources/YUtils/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "bazPkg",
                    path: "/bazPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BazLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BazLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: "/barPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: "/fooPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/bazPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "FooLogging",
                            dependencies: [.product(
                                name: "Logging",
                                package: "barPkg"
                            ),
                            .product(
                                name: "Logging",
                                package: "bazPkg"
                            )]
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "xPkg",
                    path: "/xPkg",
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["XUtils"]),
                    ],
                    targets: [
                        TargetDescription(name: "XUtils", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "yPkg",
                    path: "/yPkg",
                    products: [
                        ProductDescription(name: "Utils", type: .library(.automatic), targets: ["YUtils"]),
                    ],
                    targets: [
                        TargetDescription(name: "YUtils", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/xPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/yPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(
                                name: "Logging",
                                package: "fooPkg"
                            ),
                            .product(
                                name: "Utils",
                                package: "xPkg"
                            ),
                            .product(
                                name: "Utils",
                                package: "yPkg"
                            )],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
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
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/Logging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift",
            "/bazPkg/Sources/BazLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "bazPkg",
                    path: "/bazPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BazLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BazLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: "/barPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: "/fooPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/bazPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["Logging"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "Logging",
                            dependencies: [.product(
                                name: "Logging",
                                package: "barPkg"
                            ),
                            .product(
                                name: "Logging",
                                package: "bazPkg"
                            )]
                        ),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    dependencies: [
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(
                                name: "Logging",
                                package: "fooPkg"
                            )],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
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
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: "/fooPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "FooLogging",
                            dependencies: [.product(
                                name: "Logging",
                                package: "barPkg"
                            )]
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: "/barPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    dependencies: [
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(
                                name: "Logging",
                                package: "fooPkg"
                            )],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }

    func testDuplicateProductNamesThrowError() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let fooPkg: AbsolutePath = "/fooPkg"
        let barPkg: AbsolutePath = "/barPkg"

        XCTAssertThrowsError(try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: fooPkg,
                    toolsVersion: .v5_8,
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: barPkg,
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    dependencies: [
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(name: "Logging", package: "fooPkg"),
                                           .product(name: "Logging", package: "barPkg")],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )) { error in
            XCTAssertEqual(
                (error as? PackageGraphError)?.description,
                "multiple packages (\'barpkg\' (at '\(barPkg)'), \'foopkg\' (at '\(fooPkg)')) declare products with a conflicting name: \'Logging’; product names need to be unique across the package graph"
            )
        }
    }

    func testDuplicateProductNamesAllowed() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: "/fooPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "FooLogging", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: "/barPkg",
                    products: [
                        ProductDescription(name: "Logging", type: .library(.automatic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "2.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(
                                name: "Logging",
                                package: "fooPkg"
                            ),
                            .product(
                                name: "Logging",
                                package: "barPkg"
                            )],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
    }

    func testPackageNameFlag() async throws {
        try XCTSkipIfCI() // test is disabled because it isn't stable, see rdar://118239206
        let isFlagSupportedInDriver = try DriverSupport.checkToolchainDriverFlags(
            flags: ["package-name"],
            toolchain: UserToolchain.default,
            fileSystem: localFileSystem
        )
        try await fixture(name: "Miscellaneous/PackageNameFlag") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(fixturePath.appending("appPkg"), extraArgs: ["-vv"])
            XCTAssertMatch(stdout, .contains("-module-name Foo"))
            XCTAssertMatch(stdout, .contains("-module-name Zoo"))
            XCTAssertMatch(stdout, .contains("-module-name Bar"))
            XCTAssertMatch(stdout, .contains("-module-name Baz"))
            XCTAssertMatch(stdout, .contains("-module-name App"))
            XCTAssertMatch(stdout, .contains("-module-name exe"))
            if isFlagSupportedInDriver {
                XCTAssertMatch(stdout, .contains("-package-name apppkg"))
                XCTAssertMatch(stdout, .contains("-package-name foopkg"))
                // the flag is not supported if tools-version < 5.9
                XCTAssertNoMatch(stdout, .contains("-package-name barpkg"))
            } else {
                XCTAssertNoMatch(stdout, .contains("-package-name"))
            }
            XCTAssertMatch(stdout, .contains("Build complete!"))
        }
    }

    #if os(macOS)
    func testPackageNameFlagXCBuild() async throws {
        let isFlagSupportedInDriver = try DriverSupport.checkToolchainDriverFlags(
            flags: ["package-name"],
            toolchain: UserToolchain.default,
            fileSystem: localFileSystem
        )
        try await fixture(name: "Miscellaneous/PackageNameFlag") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath.appending("appPkg"),
                extraArgs: ["--build-system", "xcode", "-vv"]
            )
            XCTAssertMatch(stdout, .contains("-module-name Foo"))
            XCTAssertMatch(stdout, .contains("-module-name Zoo"))
            XCTAssertMatch(stdout, .contains("-module-name Bar"))
            XCTAssertMatch(stdout, .contains("-module-name Baz"))
            XCTAssertMatch(stdout, .contains("-module-name App"))
            XCTAssertMatch(stdout, .contains("-module-name exe"))
            if isFlagSupportedInDriver {
                XCTAssertMatch(stdout, .contains("-package-name apppkg"))
                XCTAssertMatch(stdout, .contains("-package-name foopkg"))
                // the flag is not supported if tools-version < 5.9
                XCTAssertNoMatch(stdout, .contains("-package-name barpkg"))
            } else {
                XCTAssertNoMatch(stdout, .contains("-package-name"))
            }
            XCTAssertMatch(stdout, .contains("Build succeeded"))
        }
    }
    #endif

    func testTargetsWithPackageAccess() async throws {
        let isFlagSupportedInDriver = try DriverSupport.checkToolchainDriverFlags(
            flags: ["package-name"],
            toolchain: UserToolchain.default,
            fileSystem: localFileSystem
        )
        try await fixture(name: "Miscellaneous/TargetPackageAccess") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(fixturePath.appending("libPkg"), extraArgs: ["-v"])
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
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath = plan.productsBuildPath

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        let lib = try result.moduleBuildDescription(for: "lib").swift().compileArguments()
        XCTAssertMatch(
            lib,
            [
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        #if os(macOS)
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker",
            buildPath.appending(components: "Modules", "lib.swiftmodule").pathString,
            "-Xlinker", "-add_ast_path", "-Xlinker",
            buildPath.appending(components: "exe.build", "exe.swiftmodule").pathString,
            "-g",
        ]
        #elseif os(Windows)
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            // "-static-stdlib",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ]
        #else
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-static-stdlib",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
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
            let main = aPath.appending("main.swift")
            let aSwift = aPath.appending("A.swift")
            let bSwift = bPath.appending("B.swift")
            let cSwift = cPath.appending("C.swift")
            try localFileSystem.writeFileContents(main, string: "baz();")
            try localFileSystem.writeFileContents(
                aSwift,
                string:
                """
                import B;\
                import C;\
                public func baz() { bar() }
                """
            )
            try localFileSystem.writeFileContents(
                bSwift,
                string:
                """
                import C;
                public func bar() { foo() }
                """
            )
            try localFileSystem.writeFileContents(
                cSwift,
                string:
                "public func foo() {}"
            )

            // Plan package build with explicit module build
            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadModulesGraph(
                fileSystem: fs,
                manifests: [
                    Manifest.createRootManifest(
                        displayName: "ExplicitTest",
                        path: testDirPath,
                        targets: [
                            TargetDescription(name: "A", dependencies: ["B"]),
                            TargetDescription(name: "B", dependencies: ["C"]),
                            TargetDescription(name: "C", dependencies: []),
                        ]
                    ),
                ],
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            do {
                let plan = try mockBuildPlan(
                    config: .release,
                    triple: UserToolchain.default.targetTriple,
                    toolchain: UserToolchain.default,
                    graph: graph,
                    driverParameters: .init(
                        useExplicitModuleBuild: true
                    ),
                    fileSystem: fs,
                    observabilityScope: observability.topScope
                )

                let yaml = buildDirPath.appending("release.yaml")
                let llbuild = LLBuildManifestBuilder(
                    plan,
                    fileSystem: localFileSystem,
                    observabilityScope: observability.topScope
                )
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
        let Pkg: AbsolutePath = "/Pkg"

        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "PkgLib", "lib.swift").pathString,
            "/ExtPkg/Sources/ExtLib/lib.swift",
            "/PlatformPkg/Sources/PlatformLib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    dependencies: [
                        .localSourceControl(path: "/ExtPkg", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/PlatformPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .target(name: "PkgLib", condition: PackageConditionDescription(
                                platformNames: ["linux", "android"],
                                config: nil
                            )),
                        ]),
                        TargetDescription(name: "PkgLib", dependencies: [
                            .product(name: "ExtLib", package: "ExtPkg", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            )),
                            .product(
                                name: "PlatformLib",
                                package: "PlatformPkg",
                                condition: PackageConditionDescription(
                                    platformNames: ["linux"]
                                )
                            ),
                        ]),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "ExtPkg",
                    path: "/ExtPkg",
                    products: [
                        ProductDescription(name: "ExtLib", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "PlatformPkg",
                    path: "/PlatformPkg",
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
            let plan = try mockBuildPlan(
                environment: BuildEnvironment(
                    platform: .linux,
                    configuration: .release
                ),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            let buildPath = plan.destinationBuildParameters.dataPath.appending(components: "release")

            let result = try BuildPlanResult(plan: plan)
            let buildProduct = try result.buildProduct(for: "exe")
            let objectDirectoryNames = buildProduct.objects.map(\.parentDirectory.basename)
            XCTAssertTrue(objectDirectoryNames.contains("PkgLib.build"))
            XCTAssertFalse(objectDirectoryNames.contains("ExtLib.build"))

            let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "release.yaml")
            try fs.createDirectory(yaml.parentDirectory, recursive: true)
            let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            try llbuild.generateManifest(at: yaml)
            let contents: String = try fs.readFileContents(yaml)
            let swiftGetVersionFilePath = try XCTUnwrap(llbuild.swiftGetVersionFiles.first?.value)
            XCTAssertMatch(
                contents,
                .contains("""
                inputs: ["\(
                    Pkg.appending(components: "Sources", "exe", "main.swift")
                        .escapedPathString
                )","\(swiftGetVersionFilePath.escapedPathString)","\(
                buildPath
                    .appending(components: "Modules", "PkgLib.swiftmodule").escapedPathString
                )","\(
                buildPath
                    .appending(components: "exe.build", "sources").escapedPathString
                )"]
                """)
            )
        }

        do {
            let plan = try mockBuildPlan(
                environment: BuildEnvironment(
                    platform: .macOS,
                    configuration: .debug
                ),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            let result = try BuildPlanResult(plan: plan)
            let buildProduct = try result.buildProduct(for: "exe")
            let objectDirectoryNames = buildProduct.objects.map(\.parentDirectory.basename)
            XCTAssertFalse(objectDirectoryNames.contains("PkgLib.build"))
            XCTAssertFalse(objectDirectoryNames.contains("ExtLib.build"))

            let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
            try fs.createDirectory(yaml.parentDirectory, recursive: true)
            let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
            try llbuild.generateManifest(at: yaml)
            let contents: String = try fs.readFileContents(yaml)
            let buildPath = plan.productsBuildPath
            let swiftGetVersionFilePath = try XCTUnwrap(llbuild.swiftGetVersionFiles.first?.value)
            XCTAssertMatch(contents, .contains("""
                inputs: ["\(
                    Pkg.appending(components: "Sources", "exe", "main.swift")
                        .escapedPathString
            )","\(swiftGetVersionFilePath.escapedPathString)","\(
                buildPath
                    .appending(components: "exe.build", "sources").escapedPathString
            )"]
            """))
        }
    }

    func testBasicExtPackages() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Tests/ATargetTests/foo.swift",
            "/B/Sources/BTarget/foo.swift",
            "/B/Tests/BTargetTests/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                        TargetDescription(name: "ATargetTests", dependencies: ["ATarget"], type: .test),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                        TargetDescription(name: "BTargetTests", dependencies: ["BTarget"], type: .test),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        XCTAssertEqual(Set(result.productMap.keys.map(\.productName)), ["APackageTests"])
        #if os(macOS)
        XCTAssertEqual(Set(result.targetMap.keys.map(\.moduleName)), ["ATarget", "BTarget", "ATargetTests"])
        #else
        XCTAssertEqual(Set(result.targetMap.keys.map(\.moduleName)), [
            "APackageTests",
            "APackageDiscoveredTests",
            "ATarget",
            "ATargetTests",
            "BTarget",
        ])
        #endif
    }

    func testBasicReleasePackage() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            config: .release,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath = result.plan.destinationBuildParameters.dataPath.appending(components: "release")

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-O",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
            ]
        )

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-dead_strip",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "/OPT:REF",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "--gc-sections",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif
    }

    func testBasicReleasePackageNoDeadStrip() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            config: .release,
            graph: graph,
            linkingParameters: .init(
                linkerDeadStrip: false
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath = result.plan.destinationBuildParameters.dataPath.appending(components: "release")

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-O",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
            ]
        )

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif
    }

    func testBasicClangPackage() throws {
        let Pkg: AbsolutePath = "/Pkg"
        let ExtPkg: AbsolutePath = "/ExtPkg"

        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.c").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.S").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString,
            ExtPkg.appending(components: "Sources", "extlib", "extlib.c").pathString,
            ExtPkg.appending(components: "Sources", "extlib", "include", "ext.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    dependencies: [
                        .localSourceControl(
                            path: .init(validating: ExtPkg.pathString),
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: ["ExtPkg"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "ExtPkg",
                    path: .init(validating: ExtPkg.pathString),
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["extlib"]),
                    ],
                    targets: [
                        TargetDescription(name: "extlib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let buildPath = result.plan.destinationBuildParameters.dataPath.appending(components: "debug")

        let ext = try result.moduleBuildDescription(for: "extlib").clang()
        var args: [String] = []

        #if os(macOS)
        args += ["-fobjc-arc"]
        #endif
        args += ["-target", defaultTargetTriple]
        args += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks"]
        #if os(macOS) // FIXME(5473) - support modules on non-Apple platforms
        args += [
            "-fmodules",
            "-fmodule-name=extlib",
            "-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))",
        ]
        #endif
        args += ["-I", ExtPkg.appending(components: "Sources", "extlib", "include").pathString]
        args += [hostTriple.isWindows() ? "-gdwarf" : "-g"]

        if hostTriple.isLinux() {
            args += ["-fno-omit-frame-pointer"]
        }

        XCTAssertEqual(try ext.basicArguments(isCXX: false), args)
        XCTAssertEqual(try ext.objects, [buildPath.appending(components: "extlib.build", "extlib.c.o")])
        XCTAssertEqual(ext.moduleMap, buildPath.appending(components: "extlib.build", "module.modulemap"))

        let exe = try result.moduleBuildDescription(for: "exe").clang()
        args = []

        #if os(macOS)
        args += ["-fobjc-arc", "-target", defaultTargetTriple]
        #else
        args += ["-target", defaultTargetTriple]
        #endif

        args += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks"]
        #if os(macOS) // FIXME(5473) - support modules on non-Apple platforms
        args += [
            "-fmodules",
            "-fmodule-name=exe",
            "-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))",
        ]
        #endif
        args += [
            "-I", Pkg.appending(components: "Sources", "exe", "include").pathString,
            "-I", Pkg.appending(components: "Sources", "lib", "include").pathString,
            "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))",
            "-I", ExtPkg.appending(components: "Sources", "extlib", "include").pathString,
            "-fmodule-map-file=\(buildPath.appending(components: "extlib.build", "module.modulemap"))",
        ]
        args += [hostTriple.isWindows() ? "-gdwarf" : "-g"]

        if hostTriple.isLinux() {
            args += ["-fno-omit-frame-pointer"]
        }

        XCTAssertEqual(try exe.basicArguments(isCXX: false), args)
        XCTAssertEqual(try exe.objects, [buildPath.appending(components: "exe.build", "main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif

        let buildProduct = try XCTUnwrap(
            result.productMap[.init(
                productName: "exe",
                packageIdentity: "Pkg",
                buildTriple: .destination
            )]
        )
        XCTAssertEqual(Array(buildProduct.objects), [
            buildPath.appending(components: "exe.build", "main.c.o"),
            buildPath.appending(components: "extlib.build", "extlib.c.o"),
            buildPath.appending(components: "lib.build", "lib.c.o"),
        ])
    }

    func testClangConditionalDependency() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.c",
            "/Pkg/Sources/PkgLib/lib.c",
            "/Pkg/Sources/PkgLib/lib.S",
            "/Pkg/Sources/PkgLib/include/lib.h",
            "/ExtPkg/Sources/ExtLib/extlib.c",
            "/ExtPkg/Sources/ExtLib/include/ext.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    dependencies: [
                        .localSourceControl(path: "/ExtPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .target(name: "PkgLib", condition: PackageConditionDescription(
                                platformNames: ["linux", "android"],
                                config: nil
                            )),
                        ]),
                        TargetDescription(name: "PkgLib", dependencies: [
                            .product(name: "ExtPkg", package: "ExtPkg", condition: PackageConditionDescription(
                                platformNames: [],
                                config: "debug"
                            )),
                        ]),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "ExtPkg",
                    path: "/ExtPkg",
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        do {
            let result = try BuildPlanResult(plan: mockBuildPlan(
                environment: BuildEnvironment(
                    platform: .linux,
                    configuration: .release
                ),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let exeArguments = try result.moduleBuildDescription(for: "exe").clang().basicArguments(isCXX: false)
            XCTAssert(exeArguments.contains { $0.contains("PkgLib") })
            XCTAssert(exeArguments.allSatisfy { !$0.contains("ExtLib") })

            let libArguments = try result.moduleBuildDescription(for: "PkgLib").clang().basicArguments(isCXX: false)
            XCTAssert(libArguments.allSatisfy { !$0.contains("ExtLib") })
        }

        do {
            let result = try BuildPlanResult(plan: mockBuildPlan(
                environment: BuildEnvironment(
                    platform: .macOS,
                    configuration: .debug
                ),
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let arguments = try result.moduleBuildDescription(for: "exe").clang().basicArguments(isCXX: false)
            XCTAssert(arguments.allSatisfy { !$0.contains("PkgLib") && !$0.contains("ExtLib") })

            let libArguments = try result.moduleBuildDescription(for: "PkgLib").clang().basicArguments(isCXX: false)
            XCTAssert(libArguments.contains { $0.contains("ExtLib") })
        }
    }

    func testCLanguageStandard() throws {
        let Pkg: AbsolutePath = "/Pkg"

        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.cpp").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "libx.cpp").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString,
            Pkg.appending(components: "Sources", "swiftInteropLib", "lib.swift").pathString,
            Pkg.appending(components: "Sources", "swiftLib", "lib.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    cLanguageStandard: "gnu99",
                    cxxLanguageStandard: "c++1z",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(
                            name: "swiftInteropLib",
                            dependencies: [],
                            settings: [.init(tool: .swift, kind: .interoperabilityMode(.Cxx))]
                        ),
                        TargetDescription(name: "swiftLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        result.checkProductsCount(1)
        result.checkTargetsCount(4)

        let buildPath = plan.productsBuildPath

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-lc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-lstdc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(
            contents,
            .contains(#"-std=gnu99","-c","\#(Pkg.appending(components: "Sources", "lib", "lib.c").escapedPathString)"#)
        )
        XCTAssertMatch(
            contents,
            .contains(
                #"-std=c++1z","-c","\#(Pkg.appending(components: "Sources", "lib", "libx.cpp").escapedPathString)"#
            )
        )

        // Assert compile args for swift modules importing cxx modules
        let swiftInteropLib = try result.moduleBuildDescription(for: "swiftInteropLib").swift().compileArguments()
        XCTAssertMatch(
            swiftInteropLib,
            [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++1z", .anySequence]
        )
        let swiftLib = try result.moduleBuildDescription(for: "swiftLib").swift().compileArguments()
        XCTAssertNoMatch(swiftLib, [.anySequence, "-Xcc", "-std=c++1z", .anySequence])

        // Assert symbolgraph-extract args for swift modules importing cxx modules
        do {
            let swiftInteropLib = try result.moduleBuildDescription(for: "swiftInteropLib").swift().compileArguments()
            XCTAssertMatch(
                swiftInteropLib,
                [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++1z", .anySequence]
            )
            let swiftLib = try result.moduleBuildDescription(for: "swiftLib").swift().compileArguments()
            XCTAssertNoMatch(swiftLib, [.anySequence, "-Xcc", "-std=c++1z", .anySequence])
        }

        // Assert symbolgraph-extract args for cxx modules
        do {
            let swiftInteropLib = try result.moduleBuildDescription(for: "swiftInteropLib").swift().compileArguments()
            XCTAssertMatch(
                swiftInteropLib,
                [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++1z", .anySequence]
            )
            let swiftLib = try result.moduleBuildDescription(for: "swiftLib").swift().compileArguments()
            XCTAssertNoMatch(swiftLib, [.anySequence, "-Xcc", "-std=c++1z", .anySequence])
        }
    }

    func testSwiftCMixed() throws {
        let Pkg: AbsolutePath = "/Pkg"

        let fs = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath = plan.productsBuildPath

        let lib = try result.moduleBuildDescription(for: "lib").clang()
        var args: [String] = []

        #if os(macOS)
        args += ["-fobjc-arc"]
        #endif
        args += ["-target", defaultTargetTriple]

        args += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1"]
        args += ["-fblocks"]
        #if os(macOS) // FIXME(5473) - support modules on non-Apple platforms
        args += [
            "-fmodules",
            "-fmodule-name=lib",
            "-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))",
        ]
        #endif
        args += ["-I", Pkg.appending(components: "Sources", "lib", "include").pathString]
        args += [hostTriple.isWindows() ? "-gdwarf" : "-g"]

        if hostTriple.isLinux() {
            args += ["-fno-omit-frame-pointer"]
        }

        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.c.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(
            exe,
            [
                .anySequence,
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-Xcc",
                "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))",
                "-Xcc", "-I", "-Xcc", "\(Pkg.appending(components: "Sources", "lib", "include"))",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker", "/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/exe.build/exe.swiftmodule",
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif
    }

    func testSwiftCAsmMixed() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/lib.S",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: .v5,
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let lib = try result.moduleBuildDescription(for: "lib").clang()
        XCTAssertEqual(try lib.objects, [
            AbsolutePath("/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/lib.build/lib.S.o"),
            AbsolutePath("/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/lib.build/lib.c.o"),
        ])
    }

    func testSwiftSettings_interoperabilityMode_cxx() throws {
        let Pkg: AbsolutePath = "/Pkg"

        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "cxxLib", "lib.cpp").pathString,
            Pkg.appending(components: "Sources", "cxxLib", "include", "lib.h").pathString,
            Pkg.appending(components: "Sources", "swiftLib", "lib.swift").pathString,
            Pkg.appending(components: "Sources", "swiftLib2", "lib2.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    cxxLanguageStandard: "c++20",
                    targets: [
                        TargetDescription(name: "cxxLib", dependencies: []),
                        TargetDescription(
                            name: "swiftLib",
                            dependencies: ["cxxLib"],
                            settings: [.init(tool: .swift, kind: .interoperabilityMode(.Cxx))]
                        ),
                        TargetDescription(name: "swiftLib2", dependencies: ["swiftLib"]),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        // Cxx module
        do {
            try XCTAssertMatch(
                result.moduleBuildDescription(for: "cxxLib").clang().symbolGraphExtractArguments(),
                [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++20", .anySequence]
            )
        }

        // Swift module directly importing cxx module
        do {
            try XCTAssertMatch(
                result.moduleBuildDescription(for: "swiftLib").swift().compileArguments(),
                [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++20", .anySequence]
            )
            try XCTAssertMatch(
                result.moduleBuildDescription(for: "swiftLib").swift().symbolGraphExtractArguments(),
                [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++20", .anySequence]
            )
        }

        // Swift module transitively importing cxx module
        do {
            try XCTAssertNoMatch(
                result.moduleBuildDescription(for: "swiftLib2").swift().compileArguments(),
                [.anySequence, "-cxx-interoperability-mode=default", .anySequence]
            )
            try XCTAssertNoMatch(
                result.moduleBuildDescription(for: "swiftLib2").swift().compileArguments(),
                [.anySequence, "-Xcc", "-std=c++20", .anySequence]
            )
            try XCTAssertNoMatch(
                result.moduleBuildDescription(for: "swiftLib2").swift().symbolGraphExtractArguments(),
                [.anySequence, "-cxx-interoperability-mode=default", .anySequence]
            )
            try XCTAssertNoMatch(
                result.moduleBuildDescription(for: "swiftLib2").swift().symbolGraphExtractArguments(),
                [.anySequence, "-Xcc", "-std=c++20", .anySequence]
            )
        }
    }

    func test_symbolGraphExtract_arguments() throws {
        // ModuleGraph:
        // .
        // ├── A (Swift)
        // │   ├── B (Swift)
        // │   └── C (C)
        // └── D (C)
        //     ├── B (Swift)
        //     └── C (C)

        let Pkg: AbsolutePath = "/Pkg"
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            // A
            Pkg.appending(components: "Sources", "A", "A.swift").pathString,
            // B
            Pkg.appending(components: "Sources", "B", "B.swift").pathString,
            // C
            Pkg.appending(components: "Sources", "C", "C.c").pathString,
            Pkg.appending(components: "Sources", "C", "include", "C.h").pathString,
            // D
            Pkg.appending(components: "Sources", "D", "D.c").pathString,
            Pkg.appending(components: "Sources", "D", "include", "D.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    targets: [
                        TargetDescription(name: "A", dependencies: ["B", "C"]),
                        TargetDescription(name: "B", dependencies: []),
                        TargetDescription(name: "C", dependencies: []),
                        TargetDescription(name: "D", dependencies: ["B", "C"]),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let result = try BuildPlanResult(plan: plan)
        let triple = result.plan.destinationBuildParameters.triple

        func XCTAssertMatchesSubSequences(
            _ value: [String],
            _ patterns: [StringPattern]...,
            file: StaticString = #file,
            line: UInt = #line
        ) {
            for pattern in patterns {
                var pattern = pattern
                pattern.insert(.anySequence, at: 0)
                pattern.append(.anySequence)
                XCTAssertMatch(value, pattern, file: file, line: line)
            }
        }

        // A
        do {
            try XCTAssertMatchesSubSequences(
                result.moduleBuildDescription(for: "A").symbolGraphExtractArguments(),
                // Swift Module dependencies
                ["-I", "/path/to/build/\(triple)/debug/Modules"],
                // C Module dependencies
                ["-Xcc", "-I", "-Xcc", "/Pkg/Sources/C/include"],
                ["-Xcc", "-fmodule-map-file=/path/to/build/\(triple)/debug/C.build/module.modulemap"]
            )
        }

        // D
        do {
            try XCTAssertMatchesSubSequences(
                result.moduleBuildDescription(for: "D").symbolGraphExtractArguments(),
                // Self Module
                ["-I", "/Pkg/Sources/D/include"],
                ["-Xcc", "-fmodule-map-file=/path/to/build/\(triple)/debug/D.build/module.modulemap"],

                // C Module dependencies
                ["-Xcc", "-I", "-Xcc", "/Pkg/Sources/C/include"],
                ["-Xcc", "-fmodule-map-file=/path/to/build/\(triple)/debug/C.build/module.modulemap"],

                // General Args
                [
                    "-Xcc", "-fmodules",
                    "-Xcc", "-fmodule-name=D",
                    "-Xcc", "-fmodules-cache-path=/path/to/build/\(triple)/debug/ModuleCache",
                ]
            )

#if os(macOS)
            try XCTAssertMatchesSubSequences(
                result.moduleBuildDescription(for: "D").symbolGraphExtractArguments(),
                // Swift Module dependencies
                ["-Xcc", "-fmodule-map-file=/path/to/build/\(triple)/debug/B.build/module.modulemap"]
            )
#endif
        }
    }

    func testREPLArguments() throws {
        let Dep = AbsolutePath("/Dep")
        let fs = InMemoryFileSystem(
            emptyFiles:
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
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    dependencies: [
                        .localSourceControl(path: "/Dep", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["swiftlib"]),
                        TargetDescription(name: "swiftlib", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: ["Dep"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    products: [
                        ProductDescription(name: "Dep", type: .library(.automatic), targets: ["Dep"]),
                    ],
                    targets: [
                        TargetDescription(name: "Dep", dependencies: ["CDep"]),
                        TargetDescription(name: "CDep", dependencies: []),
                    ]
                ),
            ],
            createREPLProduct: true,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let buildPath = plan.productsBuildPath
        XCTAssertEqual(
            try plan.createREPLArguments().sorted(),
            [
                "-I\(Dep.appending(components: "Sources", "CDep", "include"))",
                "-I\(buildPath)",
                "-I\(buildPath.appending(components: "lib.build"))",
                "-L\(buildPath)",
                "-lpkg__REPL",
                "repl",
            ]
        )

        XCTAssertEqual(plan.graph.allProducts.map(\.name).sorted(), [
            "Dep",
            "exe",
            "pkg__REPL",
        ])
    }

    func testTestModule() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/Foo/foo.swift",
            "/Pkg/Tests/\(SwiftModule.defaultTestEntryPointName)",
            "/Pkg/Tests/FooTests/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "FooTests", dependencies: ["Foo"], type: .test),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        #if os(macOS)
        result.checkTargetsCount(2)
        #else
        // On non-Apple platforms, when a custom entry point file is present (e.g. XCTMain.swift), there is one
        // additional target for the synthesized test entry point.
        result.checkTargetsCount(3)
        #endif

        let buildPath = result.plan.productsBuildPath

        let foo = try result.moduleBuildDescription(for: "Foo").swift().compileArguments()
        XCTAssertMatch(
            foo,
            [
                .anySequence,
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        let fooTests = try result.moduleBuildDescription(for: "FooTests").swift().compileArguments()
        XCTAssertMatch(
            fooTests,
            [
                .anySequence,
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        #if os(macOS)
        let version = MinimumDeploymentTarget.computeXCTestMinimumDeploymentTarget(for: .macOS).versionString
        let rpathsForBackdeployment: [String]
        if let version = try? Version(string: version, lenient: true), version.major < 12 {
            rpathsForBackdeployment = ["-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx"]
        } else {
            rpathsForBackdeployment = []
        }
        XCTAssertEqual(
            try result.buildProduct(for: "PkgPackageTests").linkArguments(),
            [
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o",
                buildPath.appending(components: "PkgPackageTests.xctest", "Contents", "MacOS", "PkgPackageTests")
                    .pathString,
                "-module-name", "PkgPackageTests",
                "-Xlinker", "-no_warn_duplicate_libraries",
                "-Xlinker", "-bundle",
                "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../../",
                "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
            ] + rpathsForBackdeployment + [
                "-target", "\(hostTriple.tripleString(forPlatformVersion: version))",
                "-Xlinker", "-add_ast_path", "-Xlinker",
                buildPath.appending(components: "Modules", "Foo.swiftmodule").pathString,
                "-Xlinker", "-add_ast_path", "-Xlinker",
                buildPath.appending(components: "Modules", "FooTests.swiftmodule").pathString,
                "-g",
            ]
        )
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "PkgPackageTests.xctest").pathString,
            "-module-name", "PkgPackageTests",
            "-emit-executable",
            "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "PkgPackageTests").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "PkgPackageTests.xctest").pathString,
            "-module-name", "PkgPackageTests",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif
    }

    func testConcurrencyInOS() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    platforms: [
                        PlatformDescription(name: "macos", version: "12.0"),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            config: .release,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath = result.plan.productsBuildPath

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()

        XCTAssertMatch(
            exe,
            [
                .anySequence,
                "-O",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-dead_strip",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", hostTriple.tripleString(forPlatformVersion: "12.0"),
            "-g",
        ])
        #endif
    }

    func testParseAsLibraryFlagForExe() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
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

        try fs.writeFileContents(
            "/Pkg/Sources/exe3/foo.swift",
            string: """
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe4/main.swift",
            string: """
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe5/comments.swift",
            string: """
            // @main in comment
            print("hello world")
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe6/comments.swift",
            string: """
            /* @main in comment */
            print("hello world")
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe7/comments.swift",
            string: """
            /*
            @main in comment
            */
            print("hello world")
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe8/comments.swift",
            string: """
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
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe9/comments.swift",
            string: """
            /*@main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }*/
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe10/comments.swift",
            string: """
            // @main in comment
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe11/comments.swift",
            string: """
            /* @main in comment */
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        )

        try fs.writeFileContents(
            "/Pkg/Sources/exe12/comments.swift",
            string: """
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
        )

        try fs.writeFileContents(
            "/Pkg/Snippets/TopLevelCodeSnippet.swift",
            string: """
            struct Foo {
              init() {}
              func foo() {}
            }
            let foo = Foo()
            foo.foo()
            """
        )

        try fs.writeFileContents(
            "/Pkg/Snippets/AtMainSnippet.swift",
            string: """
            @main
            struct Runner {
              static func main() {
                print("hello world")
              }
            }
            """
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
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
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(15)
        result.checkTargetsCount(15)

        XCTAssertNoDiagnostics(observability.diagnostics)

        // single source file not named main, and without @main should not have -parse-as-library.
        let exe1 = try result.moduleBuildDescription(for: "exe1").swift().emitCommandLine()
        XCTAssertNoMatch(exe1, ["-parse-as-library"])

        // single source file named main, and without @main should not have -parse-as-library.
        let exe2 = try result.moduleBuildDescription(for: "exe2").swift().emitCommandLine()
        XCTAssertNoMatch(exe2, ["-parse-as-library"])

        // single source file not named main, with @main should have -parse-as-library.
        let exe3 = try result.moduleBuildDescription(for: "exe3").swift().emitCommandLine()
        XCTAssertMatch(exe3, ["-parse-as-library"])

        // single source file named main, with @main should have -parse-as-library.
        let exe4 = try result.moduleBuildDescription(for: "exe4").swift().emitCommandLine()
        XCTAssertMatch(exe4, ["-parse-as-library"])

        // multiple source files should not have -parse-as-library.
        let exe5 = try result.moduleBuildDescription(for: "exe5").swift().emitCommandLine()
        XCTAssertNoMatch(exe5, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe6 = try result.moduleBuildDescription(for: "exe6").swift().emitCommandLine()
        XCTAssertNoMatch(exe6, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe7 = try result.moduleBuildDescription(for: "exe7").swift().emitCommandLine()
        XCTAssertNoMatch(exe7, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe8 = try result.moduleBuildDescription(for: "exe8").swift().emitCommandLine()
        XCTAssertNoMatch(exe8, ["-parse-as-library"])

        // @main in comment should not have -parse-as-library.
        let exe9 = try result.moduleBuildDescription(for: "exe9").swift().emitCommandLine()
        XCTAssertNoMatch(exe9, ["-parse-as-library"])

        // @main in comment + non-comment should have -parse-as-library.
        let exe10 = try result.moduleBuildDescription(for: "exe10").swift().emitCommandLine()
        XCTAssertMatch(exe10, ["-parse-as-library"])

        // @main in comment + non-comment should have -parse-as-library.
        let exe11 = try result.moduleBuildDescription(for: "exe11").swift().emitCommandLine()
        XCTAssertMatch(exe11, ["-parse-as-library"])

        // @main in comment + non-comment should have -parse-as-library.
        let exe12 = try result.moduleBuildDescription(for: "exe12").swift().emitCommandLine()
        XCTAssertMatch(exe12, ["-parse-as-library"])

        // multiple source files should not have -parse-as-library.
        let exe13 = try result.moduleBuildDescription(for: "exe13").swift().emitCommandLine()
        XCTAssertNoMatch(exe13, ["-parse-as-library"])

        // A snippet with top-level code should not have -parse-as-library.
        let topLevelCodeSnippet = try result.moduleBuildDescription(for: "TopLevelCodeSnippet").swift().emitCommandLine()
        XCTAssertNoMatch(topLevelCodeSnippet, ["-parse-as-library"])

        // A snippet with @main should have -parse-as-library
        let atMainSnippet = try result.moduleBuildDescription(for: "AtMainSnippet").swift().emitCommandLine()
        XCTAssertMatch(atMainSnippet, ["-parse-as-library"])
    }

    func testCModule() throws {
        let Clibgit = AbsolutePath("/Clibgit")

        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            Clibgit.appending(components: "module.modulemap").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    dependencies: [
                        .localSourceControl(
                            path: .init(validating: Clibgit.pathString),
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Clibgit",
                    path: "/Clibgit"
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        let buildPath = result.plan.productsBuildPath

        XCTAssertMatch(
            try result.moduleBuildDescription(for: "exe").swift().compileArguments(),
            [
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-Xcc", "-fmodule-map-file=\(Clibgit.appending(components: "module.modulemap"))",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path",
            "-Xlinker", buildPath.appending(components: "exe.build", "exe.swiftmodule").pathString,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif
    }

    func testCppModule() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.cpp",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        var result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        var linkArgs = try result.buildProduct(for: "exe").linkArguments()

        #if os(macOS)
        XCTAssertMatch(linkArgs, ["-lc++"])
        #elseif !os(Windows)
        XCTAssertMatch(linkArgs, ["-lstdc++"])
        #endif

        // Verify that `-lstdc++` is passed instead of `-lc++` when cross-compiling to Linux.
        result = try BuildPlanResult(plan: mockBuildPlan(
            triple: .arm64Linux,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)
        linkArgs = try result.buildProduct(for: "exe").linkArguments()

        XCTAssertMatch(linkArgs, ["-lstdc++"])
    }

    func testDynamicProducts() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Foo/Sources/Foo/main.swift",
            "/Bar/Source/Bar/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Bar",
                    path: "/Bar",
                    products: [
                        ProductDescription(name: "Bar-Baz", type: .library(.dynamic), targets: ["Bar"]),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: "/Foo",
                    dependencies: [
                        .localSourceControl(path: "/Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: ["Bar-Baz"]),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: g,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let buildPath = result.plan.productsBuildPath

        let fooLinkArgs = try result.buildProduct(for: "Foo").linkArguments()
        let barLinkArgs = try result.buildProduct(for: "Bar-Baz").linkArguments()

        #if os(macOS)
        XCTAssertEqual(fooLinkArgs, [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Foo").pathString,
            "-module-name", "Foo",
            "-lBar-Baz",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "Foo.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path",
            "-Xlinker", buildPath.appending(components: "Foo.build", "Foo.swiftmodule").pathString,
            "-g",
        ])

        XCTAssertEqual(barLinkArgs, [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "libBar-Baz.dylib").pathString,
            "-module-name", "Bar_Baz",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-library",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/libBar-Baz.dylib",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "Bar-Baz.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path",
            "-Xlinker", buildPath.appending(components: "Modules", "Bar.swiftmodule").pathString,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(fooLinkArgs, [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Foo.exe").pathString,
            "-module-name", "Foo",
            "-lBar-Baz",
            "-emit-executable",
            "@\(buildPath.appending(components: "Foo.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])

        XCTAssertEqual(barLinkArgs, [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Bar-Baz.dll").pathString,
            "-module-name", "Bar_Baz",
            "-emit-library",
            "@\(buildPath.appending(components: "Bar-Baz.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(fooLinkArgs, [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "Foo").pathString,
            "-module-name", "Foo",
            "-lBar-Baz",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "Foo.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ])

        XCTAssertEqual(barLinkArgs, [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "libBar-Baz.so").pathString,
            "-module-name", "Bar_Baz",
            "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "Bar-Baz.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
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
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    products: [
                        ProductDescription(name: "lib", type: .library(.dynamic), targets: ["lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let buildPath = result.plan.productsBuildPath

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        let lib = try result.moduleBuildDescription(for: "lib").swift().compileArguments()
        XCTAssertMatch(
            lib,
            [
                "-enable-batch-mode",
                "-Onone",
                "-enable-testing",
                .equal(self.j),
                "-DSWIFT_PACKAGE",
                "-DDEBUG",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
                .anySequence,
                "-swift-version", "4",
                "-g",
                .anySequence,
            ]
        )

        #if os(macOS)
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "liblib.dylib").pathString,
            "-module-name", "lib",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-library",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/liblib.dylib",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path", "-Xlinker",
            buildPath.appending(components: "Modules", "lib.swiftmodule").pathString,
            "-g",
        ]
        #elseif os(Windows)
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "lib.dll").pathString,
            "-module-name", "lib",
            "-emit-library",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld",
            "-Xlinker", "-debug:dwarf",
        ]
        #else
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "liblib.so").pathString,
            "-module-name", "lib",
            "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ]
        #endif

        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), linkArguments)
    }

    func testClangTargets() throws {
        let Pkg: AbsolutePath = "/Pkg"

        let fs = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.cpp").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    products: [
                        ProductDescription(name: "lib", type: .library(.dynamic), targets: ["lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "exe", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(2)
        result.checkTargetsCount(2)

        let triple = result.plan.destinationBuildParameters.triple
        let buildPath = result.plan.productsBuildPath

        let exe = try result.moduleBuildDescription(for: "exe").clang()

        var expectedExeBasicArgs = triple.isDarwin() ? ["-fobjc-arc"] : []
        expectedExeBasicArgs += ["-target", defaultTargetTriple]
        expectedExeBasicArgs += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks"]
        #if os(macOS) // FIXME(5473) - support modules on non-Apple platforms
        expectedExeBasicArgs += [
            "-fmodules",
            "-fmodule-name=exe",
            "-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"
        ]
        #endif
        expectedExeBasicArgs += ["-I", Pkg.appending(components: "Sources", "exe", "include").pathString]

        expectedExeBasicArgs += [triple.isWindows() ? "-gdwarf" : "-g"]

        if triple.isLinux() {
            expectedExeBasicArgs += ["-fno-omit-frame-pointer"]
        }

        XCTAssertEqual(try exe.basicArguments(isCXX: false), expectedExeBasicArgs)
        XCTAssertEqual(try exe.objects, [buildPath.appending(components: "exe.build", "main.c.o")])
        XCTAssertEqual(exe.moduleMap, nil)

        let lib = try result.moduleBuildDescription(for: "lib").clang()

        var expectedLibBasicArgs = triple.isDarwin() ? ["-fobjc-arc"] : []
        expectedLibBasicArgs += ["-target", defaultTargetTriple]
        expectedLibBasicArgs += ["-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1", "-fblocks"]
//        let shouldHaveModules = false // FIXME(5473) - support modules on non-Apple platforms, and also for C++ on any platform
//        if shouldHaveModules {
//            expectedLibBasicArgs += ["-fmodules", "-fmodule-name=lib"]
//        }
        expectedLibBasicArgs += ["-I", Pkg.appending(components: "Sources", "lib", "include").pathString]
//        if shouldHaveModules {
//            expectedLibBasicArgs += ["-fmodules-cache-path=\(buildPath.appending(components: "ModuleCache"))"]
//        }
        expectedLibBasicArgs += [
            triple.isWindows() ? "-gdwarf" : "-g",
            triple.isWindows() ? "-gdwarf" : "-g",
        ]

        if triple.isLinux() {
            expectedLibBasicArgs += ["-fno-omit-frame-pointer"]
        }

        XCTAssertEqual(try lib.basicArguments(isCXX: true), expectedLibBasicArgs)

        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.cpp.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        #if os(macOS)
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-lc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "liblib.dylib").pathString,
            "-module-name", "lib",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-library",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/liblib.dylib",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #elseif os(Windows)
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "lib.dll").pathString,
            "-module-name", "lib",
            "-emit-library",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ])
        #else
        XCTAssertEqual(try result.buildProduct(for: "lib").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-lstdc++",
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "liblib.so").pathString,
            "-module-name", "lib",
            "-emit-library",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "lib.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "-Xlinker", "-rpath=$ORIGIN",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-runtime-compatibility-version", "none",
            "-target", defaultTargetTriple,
            "-g",
        ])
        #endif
    }

    func testNonReachableProductsAndTargets() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/B/Sources/BTarget1/BTarget1.swift",
            "/B/Sources/BTarget2/main.swift",
            "/C/Sources/CTarget/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/C", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "aexec", type: .executable, targets: ["ATarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.static), targets: ["BTarget1"]),
                        ProductDescription(name: "bexec", type: .executable, targets: ["BTarget2"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget1", dependencies: []),
                        TargetDescription(name: "BTarget2", dependencies: []),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "C",
                    path: "/C",
                    products: [
                        ProductDescription(name: "cexec", type: .executable, targets: ["CTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "CTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        #if ENABLE_TARGET_BASED_DEPENDENCY_RESOLUTION
        XCTAssertEqual(observability.diagnostics.count, 1)
        let firstDiagnostic = observability.diagnostics.first.map(\.message)
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
        graphResult.check(modules: "ATarget", "BTarget1")
        #else
        graphResult.check(products: "BLibrary", "bexec", "aexec", "cexec")
        graphResult.check(modules: "ATarget", "BTarget1", "BTarget2", "CTarget")
        #endif

        let planResult = try BuildPlanResult(plan: mockBuildPlan(
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
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/B/Sources/BTarget1/source.swift",
            "/B/Sources/BTarget2/source.swift",
            "/B/Sources/BTarget3/source.swift",
            "/C/Sources/CTarget/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/C", requirement: .upToNextMajor(from: "1.0.0")),
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
                        ]),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "B",
                    path: "/B",
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
                    path: "/C",
                    products: [
                        ProductDescription(name: "CLibrary", type: .library(.static), targets: ["CTarget"]),
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

            let planResult = try BuildPlanResult(plan: mockBuildPlan(
                environment: linuxDebug,
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

            let planResult = try BuildPlanResult(plan: mockBuildPlan(
                environment: macosDebug,
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

            let planResult = try BuildPlanResult(plan: mockBuildPlan(
                environment: androidRelease,
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            ))
            planResult.checkProductsCount(4)
            planResult.checkTargetsCount(5)
        }
    }

    func testSystemPackageBuildPlan() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg"
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        XCTAssertThrows(BuildPlan.Error.noBuildableTarget) {
            _ = try mockBuildPlan(
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )
        }
    }

    func testPkgConfigHintDiagnostic() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Sources/BTarget/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
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
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        _ = try mockBuildPlan(
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )

        #if !os(Windows) // FIXME: pkg-config is not generally available on Windows
        XCTAssertTrue(observability.diagnostics.contains(where: {
            $0.severity == .warning &&
                $0.message.hasPrefix("you may be able to install BTarget using your system-packager")
        }), "expected PkgConfigHint diagnostics")
        #endif
    }

    func testPkgConfigGenericDiagnostic() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/A/Sources/BTarget/module.modulemap"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BTarget"]),
                        TargetDescription(
                            name: "BTarget",
                            type: .system,
                            pkgConfig: "BTarget"
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        _ = try mockBuildPlan(
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )

        let diagnostic = observability.diagnostics.last!

        XCTAssertEqual(diagnostic.message, "couldn't find pc file for BTarget")
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.metadata?.moduleName, "BTarget")
        XCTAssertEqual(diagnostic.metadata?.pcFile, "BTarget.pc")
    }

    func testWindowsTarget() throws {
        let Pkg: AbsolutePath = "/Pkg"
        let fs = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "lib", "lib.c").pathString,
            Pkg.appending(components: "Sources", "lib", "include", "lib.h").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            triple: .windows,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath = result.plan.destinationBuildParameters.dataPath.appending(components: "debug")

        let lib = try result.moduleBuildDescription(for: "lib").clang()
        let args = [
            "-target", "x86_64-unknown-windows-msvc",
            "-O0",
            "-DSWIFT_PACKAGE=1",
            "-DDEBUG=1",
            "-fblocks",
            "-I", Pkg.appending(components: "Sources", "lib", "include").pathString,
            "-gdwarf",
        ]
        XCTAssertEqual(try lib.basicArguments(isCXX: false), args)
        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.c.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(exe, [
            "-enable-batch-mode",
            "-Onone",
            "-enable-testing",
            .equal(self.j),
            "-DSWIFT_PACKAGE", "-DDEBUG",
            "-Xcc", "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))",
            "-Xcc", "-I", "-Xcc", "\(Pkg.appending(components: "Sources", "lib", "include"))",
            "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
            .anySequence,
            "-swift-version", "4",
            "-g",
            "-use-ld=lld",
            "-Xcc", "-gdwarf",
            .end,
        ])

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe", "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", "x86_64-unknown-windows-msvc",
            "-g",
            "-use-ld=lld",
            "-Xlinker", "-debug:dwarf",
        ])

        let executablePathExtension = try result.buildProduct(for: "exe").binaryPath.extension
        XCTAssertMatch(executablePathExtension, "exe")
    }

    func testEntrypointRenaming() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: .v5_5,
                    targets: [
                        TargetDescription(name: "exe", type: .executable),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        func createResult(for triple: Basics.Triple) throws -> BuildPlanResult {
            try BuildPlanResult(plan: mockBuildPlan(
                triple: triple,
                graph: graph,
                driverParameters: .init(
                    canRenameEntrypointFunctionName: true
                ),
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))
        }
        let supportingTriples: [Basics.Triple] = [.x86_64Linux, .x86_64MacOS]
        for triple in supportingTriples {
            let result = try createResult(for: triple)
            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(exe, ["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "exe_main"])
            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.contains("exe_main")])
        }

        let unsupportingTriples: [Basics.Triple] = [.wasi, .windows]
        for triple in unsupportingTriples {
            let result = try createResult(for: triple)
            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertNoMatch(exe, ["-entry-point-function-name"])
        }
    }

    func testIndexStore() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func check(for mode: BuildParameters.IndexStoreMode, config: BuildConfiguration) throws {
            let result = try BuildPlanResult(plan: mockBuildPlan(
                config: config,
                toolchain: try UserToolchain.default,
                graph: graph,
                indexStoreMode: mode,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let lib = try result.moduleBuildDescription(for: "lib").clang()
            let path = StringPattern.equal(result.plan.destinationBuildParameters.indexStore.pathString)

            XCTAssertMatch(
                try lib.basicArguments(isCXX: false),
                [.anySequence, "-index-store-path", path, .anySequence]
            )

            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-index-store-path", path, .anySequence])
        }

        try check(for: .auto, config: .debug)
        try check(for: .on, config: .debug)
        try check(for: .on, config: .release)
    }

    func testPlatforms() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.12"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        let aTarget = try result.moduleBuildDescription(for: "ATarget").swift().compileArguments()
        #if os(macOS)
        XCTAssertMatch(
            aTarget,
            [.equal("-target"), .equal(hostTriple.tripleString(forPlatformVersion: "10.13")), .anySequence]
        )
        #else
        XCTAssertMatch(aTarget, [.equal("-target"), .equal(defaultTargetTriple), .anySequence])
        #endif

        let bTarget = try result.moduleBuildDescription(for: "BTarget").swift().compileArguments()
        #if os(macOS)
        XCTAssertMatch(
            bTarget,
            [.equal("-target"), .equal(hostTriple.tripleString(forPlatformVersion: "10.13")), .anySequence]
        )
        #else
        XCTAssertMatch(bTarget, [.equal("-target"), .equal(defaultTargetTriple), .anySequence])
        #endif
    }

    func testPlatformsCustomTriple() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    platforms: [
                        PlatformDescription(name: "ios", version: "11.0"),
                        PlatformDescription(name: "macos", version: "10.13"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    platforms: [
                        PlatformDescription(name: "ios", version: "10.0"),
                        PlatformDescription(name: "macos", version: "10.12"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            triple: .init("arm64-apple-ios"),
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))

        let targetTriple = Triple.arm64iOS

        let aTarget = try result.moduleBuildDescription(for: "ATarget").swift().compileArguments()
        let expectedVersion = Platform.iOS.oldestSupportedVersion.versionString

        XCTAssertMatch(aTarget, [
            .equal("-target"),
            .equal(targetTriple.tripleString(forPlatformVersion: expectedVersion)),
            .anySequence,
        ])

        let bTarget = try result.moduleBuildDescription(for: "BTarget").swift().compileArguments()
        XCTAssertMatch(bTarget, [
            .equal("-target"),
            .equal(targetTriple.tripleString(forPlatformVersion: expectedVersion)),
            .anySequence,
        ])
    }

    func testPlatformsValidationComparesSpecifiedDarwinTriple() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                        PlatformDescription(name: "ios", version: "10"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.14"),
                        PlatformDescription(name: "ios", version: "10"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        // macOS versions are different (thus incompatible),
        // however our build triple *only specifies* `iOS`.
        // Therefore, we expect no error, as the iOS version
        // constraints above are valid.
        XCTAssertNoThrow(
            _ = try mockBuildPlan(
                triple: .arm64iOS,
                graph: graph,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            )
        )

        // For completeness, the invalid target should still throw an error.
        XCTAssertThrows(Diagnostics.fatalError) {
            _ = try mockBuildPlan(
                triple: .x86_64MacOS,
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

    func testPlatformsValidationWhenADependencyRequiresHigherOSVersionThanPackage() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/foo.swift",
            "/B/Sources/BTarget/foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.13"),
                    ],
                    toolsVersion: .v5,
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    platforms: [
                        PlatformDescription(name: "macos", version: "10.14"),
                    ],
                    toolsVersion: .v5,
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(name: "BTarget", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        XCTAssertThrows(Diagnostics.fatalError) {
            _ = try mockBuildPlan(
                triple: .x86_64MacOS,
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

        let fs = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/exe/main.swift",
            "/A/Sources/bar/bar.swift",
            "/A/Sources/cbar/barcpp.cpp",
            "/A/Sources/cbar/bar.c",
            "/A/Sources/cbar/include/bar.h",
            "/A/Tests/MySwiftTests/test.swift",

            "/B/Sources/t1/dep.swift",
            "/B/Sources/t2/dep.swift",
            "<end>"
        )

        let aManifest = try Manifest.createRootManifest(
            displayName: "A",
            path: "/A",
            toolsVersion: .v5,
            cxxLanguageStandard: "c++17",
            dependencies: [
                .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
            ],
            targets: [
                TargetDescription(
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
                TargetDescription(
                    name: "bar", dependencies: ["cbar", "Dep"],
                    settings: [
                        .init(tool: .swift, kind: .define("LINUX"), condition: .init(platformNames: ["linux"])),
                        .init(
                            tool: .swift,
                            kind: .define("RLINUX"),
                            condition: .init(platformNames: ["linux"], config: "release")
                        ),
                        .init(
                            tool: .swift,
                            kind: .define("DMACOS"),
                            condition: .init(platformNames: ["macos"], config: "debug")
                        ),
                        .init(tool: .swift, kind: .unsafeFlags(["-Isfoo", "-L", "sbar"])),
                        .init(
                            tool: .swift,
                            kind: .interoperabilityMode(.Cxx),
                            condition: .init(platformNames: ["linux"])
                        ),
                        .init(
                            tool: .swift,
                            kind: .interoperabilityMode(.Cxx),
                            condition: .init(platformNames: ["macos"])
                        ),
                        .init(tool: .swift, kind: .enableUpcomingFeature("BestFeature")),
                        .init(
                            tool: .swift,
                            kind: .enableUpcomingFeature("WorstFeature"),
                            condition: .init(platformNames: ["macos"], config: "debug")
                        ),
                    ]
                ),
                TargetDescription(
                    name: "exe", dependencies: ["bar"],
                    settings: [
                        .init(tool: .swift, kind: .define("FOO")),
                        .init(
                            tool: .swift,
                            kind: .interoperabilityMode(.C),
                            condition: .init(platformNames: ["linux"])
                        ),
                        .init(
                            tool: .swift,
                            kind: .interoperabilityMode(.Cxx),
                            condition: .init(platformNames: ["macos"])
                        ),
                        .init(
                            tool: .swift,
                            kind: .swiftLanguageVersion(.v4),
                            condition: .init(platformNames: ["macos"])
                        ),
                        .init(
                            tool: .swift,
                            kind: .swiftLanguageVersion(.v5),
                            condition: .init(platformNames: ["linux"])
                        ),
                        .init(tool: .linker, kind: .linkedLibrary("sqlite3")),
                        .init(
                            tool: .linker,
                            kind: .linkedFramework("CoreData"),
                            condition: .init(platformNames: ["macos"])
                        ),
                        .init(tool: .linker, kind: .unsafeFlags(["-Ilfoo", "-L", "lbar"])),
                    ]
                ),
                TargetDescription(
                    name: "MySwiftTests", type: .test,
                    settings: [
                        .init(tool: .swift, kind: .interoperabilityMode(.Cxx)),
                    ]
                ),
            ]
        )

        let bManifest = try Manifest.createFileSystemManifest(
            displayName: "B",
            path: "/B",
            toolsVersion: .v5,
            products: [
                ProductDescription(name: "Dep", type: .library(.automatic), targets: ["t1", "t2"]),
            ],
            targets: [
                TargetDescription(
                    name: "t1",
                    settings: [
                        .init(tool: .swift, kind: .define("DEP")),
                        .init(tool: .swift, kind: .swiftLanguageVersion(.v4), condition: .init(platformNames: ["linux"])),
                        .init(tool: .swift, kind: .swiftLanguageVersion(.v5), condition: .init(platformNames: ["macos"])),
                        .init(tool: .linker, kind: .linkedLibrary("libz")),
                    ]
                ),
                TargetDescription(
                    name: "t2",
                    settings: [
                        .init(tool: .linker, kind: .linkedLibrary("libz")),
                    ]
                ),
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [aManifest, bManifest],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func createResult(for dest: Basics.Triple) throws -> BuildPlanResult {
            try BuildPlanResult(plan: mockBuildPlan(
                triple: dest,
                graph: graph,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))
        }

        do {
            let result = try createResult(for: .x86_64Linux)

            let dep = try result.moduleBuildDescription(for: "t1").swift().compileArguments()
            XCTAssertMatch(dep, [.anySequence, "-DDEP", .anySequence])
            XCTAssertMatch(dep, [.anySequence, "-swift-version", "4", .anySequence])

            let cbar = try result.moduleBuildDescription(for: "cbar").clang().basicArguments(isCXX: false)
            XCTAssertMatch(
                cbar,
                [
                    .anySequence,
                    "-DCCC=2",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "headers"))",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "cppheaders"))",
                    "-Icfoo",
                    "-L", "cbar",
                    "-Icxxfoo",
                    "-L", "cxxbar",
                    "-g",
                    "-fno-omit-frame-pointer",
                    .end,
                ]
            )

            let bar = try result.moduleBuildDescription(for: "bar").swift().compileArguments()
            XCTAssertMatch(
                bar,
                [
                    .anySequence,
                    "-swift-version", "5",
                    "-DLINUX",
                    "-Isfoo",
                    "-L", "sbar",
                    "-cxx-interoperability-mode=default",
                    "-Xcc", "-std=c++17",
                    "-enable-upcoming-feature", "BestFeature",
                    "-g",
                    "-Xcc", "-g",
                    "-Xcc", "-fno-omit-frame-pointer",
                    .end,
                ]
            )

            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-swift-version", "5", "-DFOO", "-g", "-Xcc", "-g", "-Xcc", "-fno-omit-frame-pointer", .end])

            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(linkExe, [.anySequence, "-lsqlite3", "-llibz", "-Ilfoo", "-L", "lbar", "-g", .end])

            let testDiscovery = try result.moduleBuildDescription(for: "APackageDiscoveredTests").swift().compileArguments()
            XCTAssertMatch(testDiscovery, [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++17"])

            let testEntryPoint = try result.moduleBuildDescription(for: "APackageTests").swift().compileArguments()
            XCTAssertMatch(testEntryPoint, [.anySequence, "-cxx-interoperability-mode=default", "-Xcc", "-std=c++17"])
        }

        // omit frame pointers explicitly set to true
        do {
            let result = try BuildPlanResult(plan: mockBuildPlan(
                triple: .x86_64Linux,
                graph: graph,
                omitFramePointers: true,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let dep = try result.moduleBuildDescription(for: "t1").swift().compileArguments()
            XCTAssertMatch(dep, [.anySequence, "-DDEP", .anySequence])

            let cbar = try result.moduleBuildDescription(for: "cbar").clang().basicArguments(isCXX: false)
            XCTAssertMatch(
                cbar,
                [
                    .anySequence,
                    "-DCCC=2",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "headers"))",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "cppheaders"))",
                    "-Icfoo",
                    "-L", "cbar",
                    "-Icxxfoo",
                    "-L", "cxxbar",
                    "-g",
                    "-fomit-frame-pointer",
                    .end,
                ]
            )

            let bar = try result.moduleBuildDescription(for: "bar").swift().compileArguments()
            XCTAssertMatch(
                bar,
                [
                    .anySequence,
                    "-swift-version", "5",
                    "-DLINUX",
                    "-Isfoo",
                    "-L", "sbar",
                    "-cxx-interoperability-mode=default",
                    "-Xcc", "-std=c++17",
                    "-enable-upcoming-feature",
                    "BestFeature",
                    "-g",
                    "-Xcc", "-g",
                    "-Xcc", "-fomit-frame-pointer",
                    .end,
                ]
            )

            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-swift-version", "5", "-DFOO", "-g", "-Xcc", "-g", "-Xcc", "-fomit-frame-pointer", .end])
        }

        // omit frame pointers explicitly set to false
        do {
            let result = try BuildPlanResult(plan: mockBuildPlan(
                triple: .x86_64Linux,
                graph: graph,
                omitFramePointers: false,
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let dep = try result.moduleBuildDescription(for: "t1").swift().compileArguments()
            XCTAssertMatch(dep, [.anySequence, "-DDEP", .anySequence])

            let cbar = try result.moduleBuildDescription(for: "cbar").clang().basicArguments(isCXX: false)
            XCTAssertMatch(
                cbar,
                [
                    .anySequence,
                    "-DCCC=2",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "headers"))",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "cppheaders"))",
                    "-Icfoo",
                    "-L", "cbar",
                    "-Icxxfoo",
                    "-L", "cxxbar",
                    "-g",
                    "-fno-omit-frame-pointer",
                    .end,
                ]
            )

            let bar = try result.moduleBuildDescription(for: "bar").swift().compileArguments()
            XCTAssertMatch(
                bar,
                [
                    .anySequence,
                    "-swift-version", "5",
                    "-DLINUX",
                    "-Isfoo",
                    "-L", "sbar",
                    "-cxx-interoperability-mode=default",
                    "-Xcc", "-std=c++17",
                    "-enable-upcoming-feature",
                    "BestFeature",
                    "-g",
                    "-Xcc", "-g",
                    "-Xcc", "-fno-omit-frame-pointer",
                    .end,
                ]
            )

            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(exe, [.anySequence, "-swift-version", "5", "-DFOO", "-g", "-Xcc", "-g", "-Xcc", "-fno-omit-frame-pointer", .end])
        }

        do {
            let result = try createResult(for: .x86_64MacOS)

            let cbar = try result.moduleBuildDescription(for: "cbar").clang().basicArguments(isCXX: false)
            XCTAssertMatch(
                cbar,
                [
                    .anySequence,
                    "-DCCC=2",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "headers"))",
                    "-I\(A.appending(components: "Sources", "cbar", "Sources", "cppheaders"))",
                    "-Icfoo",
                    "-L", "cbar",
                    "-Icxxfoo",
                    "-L", "cxxbar",
                    "-g",
                    .end,
                ]
            )

            let bar = try result.moduleBuildDescription(for: "bar").swift().compileArguments()
            XCTAssertMatch(
                bar,
                [
                    .anySequence,
                    "-swift-version", "5",
                    "-DDMACOS",
                    "-Isfoo",
                    "-L", "sbar",
                    "-cxx-interoperability-mode=default",
                    "-Xcc", "-std=c++17",
                    "-enable-upcoming-feature", "BestFeature",
                    "-enable-upcoming-feature", "WorstFeature",
                    "-g",
                    "-Xcc", "-g",
                    .end,
                ]
            )

            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(
                exe,
                [
                    .anySequence,
                    "-swift-version", "4",
                    "-DFOO",
                    "-cxx-interoperability-mode=default",
                    "-Xcc", "-std=c++17",
                    "-g",
                    "-Xcc", "-g",
                    .end,
                ]
            )

            let linkExe = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(
                linkExe,
                [
                    .anySequence,
                    "-lsqlite3",
                    "-llibz",
                    "-framework", "CoreData",
                    "-framework", "best",
                    "-Ilfoo",
                    "-L", "lbar",
                    .anySequence,
                ]
            )
        }
    }

    func testExtraBuildFlags() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/exe/main.swift",
            "<end>"
        )

        let aManifest = try Manifest.createRootManifest(
            displayName: "A",
            path: "/A",
            toolsVersion: .v5,
            targets: [
                TargetDescription(name: "exe", dependencies: []),
            ]
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [aManifest],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        var flags = BuildFlags()
        flags.linkerFlags = ["-L", "/path/to/foo", "-L/path/to/foo", "-rpath=foo", "-rpath", "foo"]
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            commonFlags: flags,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let exe = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(
            exe,
            [
                .anySequence,
                "-L", "/path/to/foo",
                "-L/path/to/foo",
                "-Xlinker", "-rpath=foo",
                "-Xlinker", "-rpath",
                "-Xlinker", "foo",
            ]
        )
    }

    func testUserToolchainCompileFlags() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.c",
            "/Pkg/Sources/lib/include/lib.h"
        )
        try fs.createMockToolchain()

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    products: [
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"]),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let userSwiftSDK = try SwiftSDK(
            hostTriple: .arm64Linux,
            targetTriple: .wasi,
            toolset: .init(
                knownTools: [
                    .cCompiler: .init(extraCLIOptions: ["-I/fake/sdk/sysroot", "-clang-flag-from-json"]),
                    .swiftCompiler: .init(extraCLIOptions: ["-use-ld=lld", "-swift-flag-from-json"]),
                ],
                rootPaths: UserToolchain.mockHostToolchain(fs).swiftSDK.toolset.rootPaths
            ),
            pathsConfiguration: .init(
                sdkRootPath: "/fake/sdk",
                swiftResourcesPath: "/fake/lib/swift",
                swiftStaticResourcesPath: "/fake/lib/swift_static"
            )
        )
        let mockToolchain = try UserToolchain(swiftSDK: userSwiftSDK, environment: .mockEnvironment, fileSystem: fs)
        let commonFlags = BuildFlags(
            cCompilerFlags: ["-clang-command-line-flag"],
            swiftCompilerFlags: ["-swift-command-line-flag"]
        )

        let result = try BuildPlanResult(plan: mockBuildPlan(
            toolchain: mockToolchain,
            graph: graph,
            commonFlags: commonFlags,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath = result.plan.productsBuildPath

        let lib = try result.moduleBuildDescription(for: "lib").clang()
        var args: [StringPattern] = [.anySequence]
        args += ["--sysroot"]
        args += [
            "\(userSwiftSDK.pathsConfiguration.sdkRootPath!)",
            "-I/fake/sdk/sysroot",
            "-clang-flag-from-json",
            .anySequence,
            "-clang-command-line-flag",
        ]
        XCTAssertMatch(try lib.basicArguments(isCXX: false), args)

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(exe, [
            "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))",
            .anySequence,
            "-resource-dir", "\(AbsolutePath("/fake/lib/swift"))",
            .anySequence,
            "-swift-flag-from-json",
            .anySequence,
            "-swift-command-line-flag",
            .anySequence,
            "-Xcc", "-clang-flag-from-json",
            .anySequence,
            "-Xcc", "-clang-command-line-flag",
        ])

        let exeProduct = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(exeProduct, [
            .anySequence,
            "-resource-dir", "\(AbsolutePath("/fake/lib/swift"))",
            "-Xclang-linker", "-resource-dir",
            "-Xclang-linker", "\(AbsolutePath("/fake/lib/swift/clang"))",
            .anySequence,
        ])

        let staticResult = try BuildPlanResult(plan: mockBuildPlan(
            triple: .x86_64Linux,
            toolchain: mockToolchain,
            graph: graph,
            commonFlags: commonFlags,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let staticExe = try staticResult.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(staticExe, [
            .anySequence,
            "-resource-dir", "\(AbsolutePath("/fake/lib/swift_static"))",
            .anySequence,
        ])

        let staticExeProduct = try staticResult.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(staticExeProduct, [
            .anySequence,
            "-resource-dir", "\(AbsolutePath("/fake/lib/swift_static"))",
            "-Xclang-linker", "-resource-dir",
            "-Xclang-linker", "\(AbsolutePath("/fake/lib/swift/clang"))",
            .anySequence,
        ])
    }

    func testUserToolchainWithToolsetCompileFlags() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/cLib/cLib.c",
            "/Pkg/Sources/cLib/include/cLib.h",
            "/Pkg/Sources/cxxLib/cxxLib.c",
            "/Pkg/Sources/cxxLib/include/cxxLib.h"
        )
        try fileSystem.createMockToolchain()

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["cLib", "cxxLib"]),
                        TargetDescription(name: "cLib", dependencies: []),
                        TargetDescription(name: "cxxLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        func jsonFlag(tool: Toolset.KnownTool) -> String { "-\(tool)-flag-from-json" }
        func jsonFlag(tool: Toolset.KnownTool) -> StringPattern { .equal(jsonFlag(tool: tool)) }
        func cliFlag(tool: Toolset.KnownTool) -> String { "-\(tool)-flag-from-cli" }
        func cliFlag(tool: Toolset.KnownTool) -> StringPattern { .equal(cliFlag(tool: tool)) }

        let toolset = try Toolset(
            knownTools: [
                .cCompiler: .init(extraCLIOptions: [jsonFlag(tool: .cCompiler)]),
                .cxxCompiler: .init(extraCLIOptions: [jsonFlag(tool: .cxxCompiler)]),
                .swiftCompiler: .init(extraCLIOptions: [jsonFlag(tool: .swiftCompiler)]),
                .librarian: .init(path: "/fake/toolchain/usr/bin/librarian"),
                .linker: .init(path: "/fake/toolchain/usr/bin/linker", extraCLIOptions: [jsonFlag(tool: .linker)]),
            ],
            rootPaths: UserToolchain.mockHostToolchain(fileSystem).swiftSDK.toolset.rootPaths
        )
        let targetTriple = try Triple("armv7em-unknown-none-macho")
        let swiftSDK = SwiftSDK(
            hostTriple: .arm64Linux,
            targetTriple: targetTriple,
            toolset: toolset,
            pathsConfiguration: .init(
                sdkRootPath: "/fake/sdk",
                swiftStaticResourcesPath: "/usr/lib/swift_static/none"
            )
        )
        let toolchain = try UserToolchain(swiftSDK: swiftSDK, environment: .mockEnvironment, fileSystem: fileSystem)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            triple: targetTriple,
            toolchain: toolchain,
            graph: graph,
            commonFlags: BuildFlags(
                cCompilerFlags: [cliFlag(tool: .cCompiler)],
                cxxCompilerFlags: [cliFlag(tool: .cxxCompiler)],
                swiftCompilerFlags: [cliFlag(tool: .swiftCompiler)],
                linkerFlags: [cliFlag(tool: .linker)]
            ),
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        func XCTAssertCount<S>(
            _ expectedCount: Int,
            _ sequence: S,
            _ element: S.Element,
            file: StaticString = #filePath,
            line: UInt = #line
        ) where S: Sequence, S.Element: Equatable {
            let actualCount = sequence.filter { $0 == element }.count
            guard actualCount != expectedCount else { return }
            XCTFail(
                """
                Failed to find expected element '\(element)' in \
                '\(sequence)' \(expectedCount) time(s) but found element \
                \(actualCount) time(s).
                """,
                file: file,
                line: line
            )
        }

        // Compile C Target
        let cLibCompileArguments = try result.moduleBuildDescription(for: "cLib").clang().basicArguments(isCXX: false)
        let cLibCompileArgumentsPattern: [StringPattern] = [
            jsonFlag(tool: .cCompiler), "-g", cliFlag(tool: .cCompiler),
        ]
        XCTAssertMatch(cLibCompileArguments, cLibCompileArgumentsPattern)
        XCTAssertCount(0, cLibCompileArguments, jsonFlag(tool: .swiftCompiler))
        XCTAssertCount(0, cLibCompileArguments, cliFlag(tool: .swiftCompiler))
        XCTAssertCount(1, cLibCompileArguments, jsonFlag(tool: .cCompiler))
        XCTAssertCount(1, cLibCompileArguments, cliFlag(tool: .cCompiler))
        XCTAssertCount(0, cLibCompileArguments, jsonFlag(tool: .cxxCompiler))
        XCTAssertCount(0, cLibCompileArguments, cliFlag(tool: .cxxCompiler))
        XCTAssertCount(0, cLibCompileArguments, jsonFlag(tool: .linker))
        XCTAssertCount(0, cLibCompileArguments, cliFlag(tool: .linker))

        // Compile Cxx Target
        let cxxLibCompileArguments = try result.moduleBuildDescription(for: "cxxLib").clang().basicArguments(isCXX: true)
        let cxxLibCompileArgumentsPattern: [StringPattern] = [
            jsonFlag(tool: .cCompiler), "-g", cliFlag(tool: .cCompiler),
            .anySequence,
            jsonFlag(tool: .cxxCompiler), "-g", cliFlag(tool: .cxxCompiler),
        ]
        XCTAssertMatch(cxxLibCompileArguments, cxxLibCompileArgumentsPattern)
        XCTAssertCount(0, cxxLibCompileArguments, jsonFlag(tool: .swiftCompiler))
        XCTAssertCount(0, cxxLibCompileArguments, cliFlag(tool: .swiftCompiler))
        XCTAssertCount(1, cxxLibCompileArguments, jsonFlag(tool: .cCompiler))
        XCTAssertCount(1, cxxLibCompileArguments, cliFlag(tool: .cCompiler))
        XCTAssertCount(1, cxxLibCompileArguments, jsonFlag(tool: .cxxCompiler))
        XCTAssertCount(1, cxxLibCompileArguments, cliFlag(tool: .cxxCompiler))
        XCTAssertCount(0, cxxLibCompileArguments, jsonFlag(tool: .linker))
        XCTAssertCount(0, cxxLibCompileArguments, cliFlag(tool: .linker))

        // Compile Swift Target
        let exeCompileArguments = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        let exeCompileArgumentsPattern: [StringPattern] = [
            jsonFlag(tool: .swiftCompiler),
            "-ld-path=/fake/toolchain/usr/bin/linker",
            "-g", cliFlag(tool: .swiftCompiler),
            .anySequence,
            "-Xcc", jsonFlag(tool: .cCompiler), "-Xcc", "-g", "-Xcc", cliFlag(tool: .cCompiler),
            // TODO: Pass -Xcxx flags to swiftc (#6491)
            // Uncomment when downstream support arrives.
            // .anySequence,
            // "-Xcxx", jsonFlag(tool: .cxxCompiler), "-Xcxx", cliFlag(tool: .cxxCompiler),
        ]
        XCTAssertMatch(exeCompileArguments, exeCompileArgumentsPattern)
        XCTAssertCount(1, exeCompileArguments, jsonFlag(tool: .swiftCompiler))
        XCTAssertCount(1, exeCompileArguments, cliFlag(tool: .swiftCompiler))
        XCTAssertCount(1, exeCompileArguments, jsonFlag(tool: .cCompiler))
        XCTAssertCount(1, exeCompileArguments, cliFlag(tool: .cCompiler))
        // TODO: Pass -Xcxx flags to swiftc (#6491)
        // Change 0 to 1 when downstream support arrives.
        XCTAssertCount(0, exeCompileArguments, jsonFlag(tool: .cxxCompiler))
        XCTAssertCount(0, exeCompileArguments, cliFlag(tool: .cxxCompiler))
        XCTAssertCount(0, exeCompileArguments, jsonFlag(tool: .linker))
        XCTAssertCount(0, exeCompileArguments, cliFlag(tool: .linker))

        // Link Product
        let exeLinkArguments = try result.buildProduct(for: "exe").linkArguments()
        let exeLinkArgumentsPattern: [StringPattern] = [
            jsonFlag(tool: .swiftCompiler),
            "-ld-path=/fake/toolchain/usr/bin/linker",
            "-g", cliFlag(tool: .swiftCompiler),
            .anySequence,
            "-Xlinker", jsonFlag(tool: .linker), "-Xlinker", cliFlag(tool: .linker),
        ]
        XCTAssertMatch(exeLinkArguments, exeLinkArgumentsPattern)
        XCTAssertCount(1, exeLinkArguments, jsonFlag(tool: .swiftCompiler))
        XCTAssertCount(1, exeLinkArguments, cliFlag(tool: .swiftCompiler))
        XCTAssertCount(0, exeLinkArguments, jsonFlag(tool: .cCompiler))
        XCTAssertCount(0, exeLinkArguments, cliFlag(tool: .cCompiler))
        XCTAssertCount(0, exeLinkArguments, jsonFlag(tool: .cxxCompiler))
        XCTAssertCount(0, exeLinkArguments, cliFlag(tool: .cxxCompiler))
        XCTAssertCount(1, exeLinkArguments, jsonFlag(tool: .linker))
        XCTAssertCount(1, exeLinkArguments, cliFlag(tool: .linker))
    }

    func testUserToolchainWithSDKSearchPaths() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/cLib/cLib.c",
            "/Pkg/Sources/cLib/include/cLib.h"
        )
        try fileSystem.createMockToolchain()

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["cLib"]),
                        TargetDescription(name: "cLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let targetTriple = try UserToolchain.default.targetTriple
        let sdkIncludeSearchPath = AbsolutePath("/usr/lib/swift_static/none/include")
        let sdkLibrarySearchPath = AbsolutePath("/usr/lib/swift_static/none/lib")
        let swiftSDK = try SwiftSDK(
            targetTriple: targetTriple,
            properties: .init(
                sdkRootPath: "/fake/sdk",
                includeSearchPaths: [sdkIncludeSearchPath.pathString],
                librarySearchPaths: [sdkLibrarySearchPath.pathString]
            ),
            toolset: .init(knownTools: [
                .swiftCompiler: .init(extraCLIOptions: ["-use-ld=lld"]),
            ])
        )
        let toolchain = try UserToolchain(swiftSDK: swiftSDK, environment: .mockEnvironment, fileSystem: fileSystem)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            toolchain: toolchain,
            graph: graph,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        // Compile C Target
        let cLibCompileArguments = try result.moduleBuildDescription(for: "cLib").clang().basicArguments(isCXX: false)
        let cLibCompileArgumentsPattern: [StringPattern] = ["-I", "\(sdkIncludeSearchPath)"]
        XCTAssertMatch(cLibCompileArguments, cLibCompileArgumentsPattern)

        // Compile Swift Target
        let exeCompileArguments = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        let exeCompileArgumentsPattern: [StringPattern] = ["-I", "\(sdkIncludeSearchPath)"]
        XCTAssertMatch(exeCompileArguments, exeCompileArgumentsPattern)

        // Link Product
        let exeLinkArguments = try result.buildProduct(for: "exe").linkArguments()
        let exeLinkArgumentsPattern: [StringPattern] = ["-L", "\(sdkIncludeSearchPath)"]
        XCTAssertMatch(exeLinkArguments, exeLinkArgumentsPattern)
    }

    func testExecBuildTimeDependency() throws {
        let PkgA = AbsolutePath("/PkgA")

        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            PkgA.appending(components: "Sources", "exe", "main.swift").pathString,
            PkgA.appending(components: "Sources", "swiftlib", "lib.swift").pathString,
            "/PkgB/Sources/PkgB/PkgB.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "PkgA",
                    path: .init(validating: PkgA.pathString),
                    products: [
                        ProductDescription(name: "swiftlib", type: .library(.automatic), targets: ["swiftlib"]),
                        ProductDescription(name: "exe", type: .executable, targets: ["exe"]),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: []),
                        TargetDescription(name: "swiftlib", dependencies: ["exe"]),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "PkgB",
                    path: "/PkgB",
                    dependencies: [
                        .localSourceControl(
                            path: .init(validating: PkgA.pathString),
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                    ],
                    targets: [
                        TargetDescription(name: "PkgB", dependencies: ["swiftlib"]),
                    ]
                ),
            ],
            explicitProduct: "exe",
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let buildPath = plan.productsBuildPath

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        let swiftGetVersionFilePath = try XCTUnwrap(llbuild.swiftGetVersionFiles.first?.value)

        #if os(Windows)
        let suffix = ".exe"
        #else // FIXME(5472) - the suffix is dropped
        let suffix = ""
        #endif
        XCTAssertMatch(contents, .contains("""
            inputs: ["\(
                PkgA.appending(components: "Sources", "swiftlib", "lib.swift")
                    .escapedPathString
        )","\(swiftGetVersionFilePath.escapedPathString)","\(
            buildPath
                .appending(components: "exe\(suffix)").escapedPathString
        )","\(
            buildPath
                .appending(components: "swiftlib.build", "sources").escapedPathString
        )"]
            outputs: ["\(
                buildPath.appending(components: "swiftlib.build", "lib.swift.o")
                    .escapedPathString
        )","\(buildPath.escapedPathString)
        """))
        }

    func testObjCHeader1() throws {
        let PkgA = AbsolutePath("/PkgA")

        // This has a Swift and ObjC target in the same package.
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            PkgA.appending(components: "Sources", "Bar", "main.m").pathString,
            PkgA.appending(components: "Sources", "Foo", "Foo.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: .init(validating: PkgA.pathString),
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath = result.plan.productsBuildPath

        let fooTarget = try result.moduleBuildDescription(for: "Foo").swift().compileArguments()
        #if os(macOS)
        XCTAssertMatch(
            fooTarget,
            [
                .anySequence,
                "-emit-objc-header",
                "-emit-objc-header-path", "/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/Foo-Swift.h",
                .anySequence,
            ]
        )
        #else
        XCTAssertNoMatch(
            fooTarget,
            [
                .anySequence,
                "-emit-objc-header",
                "-emit-objc-header-path", "/path/to/build/\(result.plan.destinationBuildParameters.triple)/Foo.build/Foo-Swift.h",
                .anySequence,
            ]
        )
        #endif

        let barTarget = try result.moduleBuildDescription(for: "Bar").clang().basicArguments(isCXX: false)
        #if os(macOS)
        XCTAssertMatch(
            barTarget,
            [.anySequence, "-fmodule-map-file=/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/module.modulemap", .anySequence]
        )
        #else
        XCTAssertNoMatch(
            barTarget,
            [.anySequence, "-fmodule-map-file=/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/module.modulemap", .anySequence]
        )
        #endif

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
          "\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString)":
            tool: clang
            inputs: ["\(buildPath.appending(components: "Modules", "Foo.swiftmodule").escapedPathString)","\(PkgA
            .appending(components: "Sources", "Bar", "main.m").escapedPathString)"]
            outputs: ["\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString)"]
            description: "Compiling Bar main.m"
        """))
    }

    func testObjCHeader2() throws {
        let PkgA = AbsolutePath("/PkgA")

        // This has a Swift and ObjC target in different packages with automatic product type.
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            PkgA.appending(components: "Sources", "Bar", "main.m").pathString,
            "/PkgB/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: .init(validating: PkgA.pathString),
                    dependencies: [
                        .localSourceControl(path: "/PkgB", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "PkgB",
                    path: "/PkgB",
                    products: [
                        ProductDescription(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath = result.plan.productsBuildPath

        let fooTarget = try result.moduleBuildDescription(for: "Foo").swift().compileArguments()
        #if os(macOS)
        XCTAssertMatch(
            fooTarget,
            [
                .anySequence,
                "-emit-objc-header",
                "-emit-objc-header-path",
                "/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/Foo-Swift.h",
                .anySequence,
            ]
        )
        #else
        XCTAssertNoMatch(
            fooTarget,
            [
                .anySequence,
                "-emit-objc-header",
                "-emit-objc-header-path",
                "/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/Foo-Swift.h",
                .anySequence,
            ]
        )
        #endif

        let barTarget = try result.moduleBuildDescription(for: "Bar").clang().basicArguments(isCXX: false)
        #if os(macOS)
        XCTAssertMatch(
            barTarget,
            [
                .anySequence,
                "-fmodule-map-file=/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/module.modulemap",
                .anySequence,
            ]
        )
        #else
        XCTAssertNoMatch(
            barTarget,
            [
                .anySequence,
                "-fmodule-map-file=/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/module.modulemap",
                .anySequence,
            ]
        )
        #endif

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
          "\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString)":
            tool: clang
            inputs: ["\(buildPath.appending(components: "Modules", "Foo.swiftmodule").escapedPathString)","\(PkgA
            .appending(components: "Sources", "Bar", "main.m").escapedPathString)"]
            outputs: ["\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString)"]
            description: "Compiling Bar main.m"
        """))
    }

    func testObjCHeader3() throws {
        let PkgA = AbsolutePath("/PkgA")

        // This has a Swift and ObjC target in different packages with dynamic product type.
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            PkgA.appending(components: "Sources", "Bar", "main.m").pathString,
            "/PkgB/Sources/Foo/Foo.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: .init(validating: PkgA.pathString),
                    dependencies: [
                        .localSourceControl(path: "/PkgB", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "Bar", dependencies: ["Foo"]),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "PkgB",
                    path: "/PkgB",
                    products: [
                        ProductDescription(name: "Foo", type: .library(.dynamic), targets: ["Foo"]),
                    ],
                    targets: [
                        TargetDescription(name: "Foo", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let dynamicLibraryExtension = plan.destinationBuildParameters.triple.dynamicLibraryExtension
        #if os(Windows)
        let dynamicLibraryPrefix = ""
        #else
        let dynamicLibraryPrefix = "lib"
        #endif
        let result = try BuildPlanResult(plan: plan)

        let fooTarget = try result.moduleBuildDescription(for: "Foo").swift().compileArguments()
        #if os(macOS)
        XCTAssertMatch(
            fooTarget,
            [
                .anySequence,
                "-emit-objc-header",
                "-emit-objc-header-path",
                "/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/Foo-Swift.h",
                .anySequence,
            ]
        )
        #else
        XCTAssertNoMatch(
            fooTarget,
            [
                .anySequence,
                "-emit-objc-header",
                "-emit-objc-header-path",
                "/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/Foo-Swift.h",
                .anySequence,
            ]
        )
        #endif

        let barTarget = try result.moduleBuildDescription(for: "Bar").clang().basicArguments(isCXX: false)
        #if os(macOS)
        XCTAssertMatch(
            barTarget,
            [
                .anySequence,
                "-fmodule-map-file=/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/module.modulemap",
                .anySequence,
            ]
        )
        #else
        XCTAssertNoMatch(
            barTarget,
            [
                .anySequence,
                "-fmodule-map-file=/path/to/build/\(result.plan.destinationBuildParameters.triple)/debug/Foo.build/module.modulemap",
                .anySequence,
            ]
        )
        #endif

        let buildPath = result.plan.productsBuildPath

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
          "\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString)":
            tool: clang
            inputs: ["\(
                buildPath.appending(components: "\(dynamicLibraryPrefix)Foo\(dynamicLibraryExtension)")
                    .escapedPathString
        )","\(PkgA.appending(components: "Sources", "Bar", "main.m").escapedPathString)"]
            outputs: ["\(buildPath.appending(components: "Bar.build", "main.m.o").escapedPathString)"]
            description: "Compiling Bar main.m"
        """))
    }

    func testModulewrap() throws {
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            triple: .x86_64Linux,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let buildPath = result.plan.productsBuildPath

        let objects = try result.buildProduct(for: "exe").objects
        XCTAssertTrue(
            objects.contains(buildPath.appending(components: "exe.build", "exe.swiftmodule.o")),
            objects.description
        )
        XCTAssertTrue(
            objects.contains(buildPath.appending(components: "lib.build", "lib.swiftmodule.o")),
            objects.description
        )

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)
        let llbuild = LLBuildManifestBuilder(result.plan, fileSystem: fs, observabilityScope: observability.topScope)
        try llbuild.generateManifest(at: yaml)
        let contents: String = try fs.readFileContents(yaml)
        XCTAssertMatch(contents, .contains("""
          "\(buildPath.appending(components: "exe.build", "exe.swiftmodule.o").escapedPathString)":
            tool: shell
            inputs: ["\(buildPath.appending(components: "exe.build", "exe.swiftmodule").escapedPathString)"]
            outputs: ["\(buildPath.appending(components: "exe.build", "exe.swiftmodule.o").escapedPathString)"]
            description: "Wrapping AST for exe for debugging"
            args: ["\(
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath
                    .escapedPathString
        )","-modulewrap","\(buildPath.appending(
            components: "exe.build",
            "exe.swiftmodule"
        ).escapedPathString)","-o","\(
            buildPath.appending(components: "exe.build", "exe.swiftmodule.o")
                .escapedPathString
        )","-target","x86_64-unknown-linux-gnu"]
        """))
        XCTAssertMatch(contents, .contains("""
          "\(buildPath.appending(components: "lib.build", "lib.swiftmodule.o").escapedPathString)":
            tool: shell
            inputs: ["\(buildPath.appending(components: "Modules", "lib.swiftmodule").escapedPathString)"]
            outputs: ["\(buildPath.appending(components: "lib.build", "lib.swiftmodule.o").escapedPathString)"]
            description: "Wrapping AST for lib for debugging"
            args: ["\(
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath
                    .escapedPathString
        )","-modulewrap","\(buildPath.appending(
            components: "Modules",
            "lib.swiftmodule"
        ).escapedPathString)","-o","\(
            buildPath.appending(components: "lib.build", "lib.swiftmodule.o")
                .escapedPathString
        )","-target","x86_64-unknown-linux-gnu"]
        """))
    }

    func testArchiving() throws {
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Package/Sources/rary/rary.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Package",
                    path: "/Package",
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

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        let buildPath = result.plan.productsBuildPath

        let yaml = try fs.tempDirectory.appending(components: UUID().uuidString, "debug.yaml")
        try fs.createDirectory(yaml.parentDirectory, recursive: true)

        let llbuild = LLBuildManifestBuilder(
            result.plan,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        try llbuild.generateManifest(at: yaml)

        let contents: String = try fs.readFileContents(yaml)
        let triple = result.plan.destinationBuildParameters.triple.tripleString

        if result.plan.destinationBuildParameters.triple.isWindows() {
            XCTAssertMatch(
                contents,
                .contains("""
                "C.rary-\(triple)-debug.a":
                    tool: shell
                    inputs: ["\(
                        buildPath.appending(components: "rary.build", "rary.swift.o")
                            .escapedPathString
                    )","\(
                    buildPath.appending(components: "rary.build", "rary.swiftmodule.o")
                        .escapedPathString
                    )","\(
                    buildPath.appending(components: "rary.product", "Objects.LinkFileList")
                        .escapedPathString
                    )"]
                    outputs: ["\(buildPath.appending(components: "library.a").escapedPathString)"]
                    description: "Archiving \(buildPath.appending(components: "library.a").escapedPathString)"
                    args: ["\(
                        result.plan.destinationBuildParameters.toolchain.librarianPath
                            .escapedPathString
                    )","/LIB","/OUT:\(
                    buildPath.appending(components: "library.a")
                        .escapedPathString
                    )","@\(
                    buildPath.appending(components: "rary.product", "Objects.LinkFileList")
                        .escapedPathString
                    )"]
                """)
            )
        } else if result.plan.destinationBuildParameters.triple.isDarwin() {
            XCTAssertMatch(
                contents,
                .contains(
                """
                "C.rary-\(triple)-debug.a":
                    tool: shell
                    inputs: ["\(
                        buildPath.appending(components: "rary.build", "rary.swift.o")
                            .escapedPathString
                    )","\(
                    buildPath.appending(components: "rary.product", "Objects.LinkFileList")
                        .escapedPathString
                    )"]
                    outputs: ["\(buildPath.appending(components: "library.a").escapedPathString)"]
                    description: "Archiving \(buildPath.appending(components: "library.a").escapedPathString)"
                    args: ["\(
                        result.plan.destinationBuildParameters.toolchain.librarianPath
                            .escapedPathString
                    )","-static","-o","\(
                    buildPath.appending(components: "library.a")
                        .escapedPathString
                    )","@\(
                    buildPath.appending(components: "rary.product", "Objects.LinkFileList")
                        .escapedPathString
                    )"]
                """)
            )
        } else { // assume `llvm-ar` is the librarian
            XCTAssertMatch(
                contents,
                .contains(
                """
                "C.rary-\(triple)-debug.a":
                    tool: shell
                    inputs: ["\(
                        buildPath.appending(components: "rary.build", "rary.swift.o")
                            .escapedPathString
                    )","\(
                    buildPath.appending(components: "rary.build", "rary.swiftmodule.o")
                        .escapedPathString
                    )","\(
                    buildPath.appending(components: "rary.product", "Objects.LinkFileList")
                        .escapedPathString
                    )"]
                    outputs: ["\(buildPath.appending(components: "library.a").escapedPathString)"]
                    description: "Archiving \(buildPath.appending(components: "library.a").escapedPathString)"
                    args: ["\(
                        result.plan.destinationBuildParameters.toolchain.librarianPath
                            .escapedPathString
                    )","crs","\(
                    buildPath.appending(components: "library.a")
                        .escapedPathString
                    )","@\(
                    buildPath.appending(components: "rary.product", "Objects.LinkFileList")
                        .escapedPathString
                    )"]
                """)
            )
        }
    }

    func testSwiftBundleAccessor() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/PkgA/Sources/Foo/Foo.swift",
            "/PkgA/Sources/Foo/foo.txt",
            "/PkgA/Sources/Foo/bar.txt",
            "/PkgA/Sources/Bar/Bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: "/PkgA",
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
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath = result.plan.productsBuildPath

        let fooTarget = try result.moduleBuildDescription(for: "Foo").swift()
        XCTAssertEqual(try fooTarget.objects.map(\.pathString), [
            buildPath.appending(components: "Foo.build", "Foo.swift.o").pathString,
            buildPath.appending(components: "Foo.build", "resource_bundle_accessor.swift.o").pathString,
        ])

        let resourceAccessor = fooTarget.sources.first { $0.basename == "resource_bundle_accessor.swift" }!
        let contents: String = try fs.readFileContents(resourceAccessor)
        XCTAssertMatch(contents, .contains("extension Foundation.Bundle"))
        // Assert that `Bundle.main` is executed in the compiled binary (and not during compilation)
        // See https://bugs.swift.org/browse/SR-14555 and
        // https://github.com/swiftlang/swift-package-manager/pull/2972/files#r623861646
        XCTAssertMatch(contents, .contains("let mainPath = Bundle.main."))

        let barTarget = try result.moduleBuildDescription(for: "Bar").swift()
        XCTAssertEqual(try barTarget.objects.map(\.pathString), [
            buildPath.appending(components: "Bar.build", "Bar.swift.o").pathString,
        ])
    }

    func testSwiftWASIBundleAccessor() throws {
        // This has a Swift and ObjC target in the same package.
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/PkgA/Sources/Foo/Foo.swift",
            "/PkgA/Sources/Foo/foo.txt",
            "/PkgA/Sources/Foo/bar.txt",
            "/PkgA/Sources/Bar/Bar.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "PkgA",
                    path: "/PkgA",
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
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            triple: .wasi,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath = result.plan.productsBuildPath

        let fooTarget = try result.moduleBuildDescription(for: "Foo").swift()
        XCTAssertEqual(try fooTarget.objects.map(\.pathString), [
            buildPath.appending(components: "Foo.build", "Foo.swift.o").pathString,
            buildPath.appending(components: "Foo.build", "resource_bundle_accessor.swift.o").pathString,
        ])

        let resourceAccessor = fooTarget.sources.first { $0.basename == "resource_bundle_accessor.swift" }!
        let contents: String = try fs.readFileContents(resourceAccessor)
        XCTAssertMatch(contents, .contains("extension Foundation.Bundle"))
        // Assert that `Bundle.main` is executed in the compiled binary (and not during compilation)
        // See https://bugs.swift.org/browse/SR-14555 and
        // https://github.com/swiftlang/swift-package-manager/pull/2972/files#r623861646
        XCTAssertMatch(contents, .contains("let mainPath = \""))

        let barTarget = try result.moduleBuildDescription(for: "Bar").swift()
        XCTAssertEqual(try barTarget.objects.map(\.pathString), [
            buildPath.appending(components: "Bar.build", "Bar.swift.o").pathString,
        ])
    }

    func testClangBundleAccessor() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/Foo/include/Foo.h",
            "/Pkg/Sources/Foo/Foo.m",
            "/Pkg/Sources/Foo/bar.h",
            "/Pkg/Sources/Foo/bar.c",
            "/Pkg/Sources/Foo/resource.txt"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: .current,
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            resources: [
                                .init(
                                    rule: .process(localization: .none),
                                    path: "resource.txt"
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        let buildPath = result.plan.productsBuildPath

        let fooTarget = try result.moduleBuildDescription(for: "Foo").clang()
        XCTAssertEqual(try fooTarget.objects.map(\.pathString).sorted(), [
            buildPath.appending(components: "Foo.build", "Foo.m.o").pathString,
            buildPath.appending(components: "Foo.build", "bar.c.o").pathString,
            buildPath.appending(components: "Foo.build", "resource_bundle_accessor.m.o").pathString,
        ].sorted())

        let resourceAccessorDirectory = buildPath.appending(
            components:
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
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let supportingTriples: [Basics.Triple] = [.x86_64Linux, .arm64Linux, .wasi]
        for triple in supportingTriples {
            let result = try BuildPlanResult(plan: mockBuildPlan(
                triple: triple,
                graph: graph,
                linkingParameters: .init(
                    shouldLinkStaticSwiftStdlib: true
                ),
                fileSystem: fs,
                observabilityScope: observability.topScope
            ))

            let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
            XCTAssertMatch(exe, ["-static-stdlib"])
            let lib = try result.moduleBuildDescription(for: "lib").swift().compileArguments()
            XCTAssertMatch(lib, ["-static-stdlib"])
            let link = try result.buildProduct(for: "exe").linkArguments()
            XCTAssertMatch(link, ["-static-stdlib"])
        }
    }

    func testXCFrameworkBinaryTargets(platform: String, arch: String, targetTriple: Basics.Triple) throws {
        let Pkg: AbsolutePath = "/Pkg"

        let fs = InMemoryFileSystem(
            emptyFiles:
            Pkg.appending(components: "Sources", "exe", "main.swift").pathString,
            Pkg.appending(components: "Sources", "Library", "Library.swift").pathString,
            Pkg.appending(components: "Sources", "CLibrary", "library.c").pathString,
            Pkg.appending(components: "Sources", "CLibrary", "include", "library.h").pathString
        )

        try! fs.createDirectory("/Pkg/Framework.xcframework", recursive: true)
        try! fs.writeFileContents(
            "/Pkg/Framework.xcframework/Info.plist",
            string: """
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
            """
        )

        try! fs.createDirectory("/Pkg/StaticLibrary.xcframework", recursive: true)
        try! fs.writeFileContents(
            "/Pkg/StaticLibrary.xcframework/Info.plist",
            string: """
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
            """
        )

        let observability = ObservabilitySystem.makeForTesting()

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: Pkg.pathString),
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
                    "StaticLibrary": .init(kind: .xcframework, originURL: nil, path: "/Pkg/StaticLibrary.xcframework"),
                ],
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            triple: targetTriple,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        XCTAssertNoDiagnostics(observability.diagnostics)

        result.checkProductsCount(3)
        result.checkTargetsCount(3)

        let buildPath = result.plan.productsBuildPath

        let libraryBasicArguments = try result.moduleBuildDescription(for: "Library").swift().compileArguments()
        XCTAssertMatch(libraryBasicArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])

        let libraryLinkArguments = try result.buildProduct(for: "Library").linkArguments()
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-L", "\(buildPath)", .anySequence])
        XCTAssertMatch(libraryLinkArguments, [.anySequence, "-framework", "Framework", .anySequence])

        let exeCompileArguments = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(exeCompileArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(
            exeCompileArguments,
            [
                .anySequence,
                "-I",
                "\(Pkg.appending(components: "Framework.xcframework", "\(platform)-\(arch)"))",
                .anySequence,
            ]
        )

        let exeLinkArguments = try result.buildProduct(for: "exe").linkArguments()
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-L", "\(buildPath)", .anySequence])
        XCTAssertMatch(exeLinkArguments, [.anySequence, "-framework", "Framework", .anySequence])

        let clibraryBasicArguments = try result.moduleBuildDescription(for: "CLibrary").clang().basicArguments(isCXX: false)
        XCTAssertMatch(clibraryBasicArguments, [.anySequence, "-F", "\(buildPath)", .anySequence])
        XCTAssertMatch(
            clibraryBasicArguments,
            [
                .anySequence,
                "-I", "\(Pkg.appending(components: "StaticLibrary.xcframework", "\(platform)-\(arch)", "Headers"))",
                .anySequence,
            ]
        )

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
        try self.testXCFrameworkBinaryTargets(platform: "macos", arch: "x86_64", targetTriple: .x86_64MacOS)

        let arm64Triple = try Basics.Triple("arm64-apple-macosx")
        try self.testXCFrameworkBinaryTargets(platform: "macos", arch: "arm64", targetTriple: arm64Triple)

        let arm64eTriple = try Basics.Triple("arm64e-apple-macosx")
        try self.testXCFrameworkBinaryTargets(platform: "macos", arch: "arm64e", targetTriple: arm64eTriple)
    }

    func testArtifactsArchiveBinaryTargets(
        artifactTriples: [Basics.Triple],
        targetTriple: Basics.Triple
    ) throws -> Bool {
        let fs = InMemoryFileSystem(emptyFiles: "/Pkg/Sources/exe/main.swift")

        let artifactName = "my-tool"
        let toolPath = AbsolutePath("/Pkg/MyTool.artifactbundle")
        try fs.createDirectory(toolPath, recursive: true)

        try fs.writeFileContents(
            toolPath.appending("info.json"),
            string: """
                {
                    "schemaVersion": "1.0",
                    "artifacts": {
                        "\(artifactName)": {
                            "type": "executable",
                            "version": "1.1.0",
                            "variants": [
                                {
                                    "path": "all-platforms/mytool",
                                    "supportedTriples": ["\(
                                        artifactTriples.map(\.tripleString)
                                            .joined(separator: "\", \""))"]
                                }
                            ]
                        }
                    }
                }
            """
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
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
                ],
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            triple: targetTriple,
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
        XCTAssertTrue(try self.testArtifactsArchiveBinaryTargets(
            artifactTriples: [.x86_64MacOS],
            targetTriple: .x86_64MacOS
        ))

        do {
            let triples = try ["arm64-apple-macosx", "x86_64-apple-macosx", "x86_64-unknown-linux-gnu"]
                .map(Basics.Triple.init)
            XCTAssertTrue(try self.testArtifactsArchiveBinaryTargets(
                artifactTriples: triples,
                targetTriple: triples.first!
            ))
        }

        do {
            let triples = try ["x86_64-unknown-linux-gnu"].map(Basics.Triple.init)
            XCTAssertFalse(try self.testArtifactsArchiveBinaryTargets(
                artifactTriples: triples,
                targetTriple: .x86_64MacOS
            ))
        }
    }

    func testAddressSanitizer() throws {
        try self.sanitizerTest(.address, expectedName: "address")
    }

    func testThreadSanitizer() throws {
        try self.sanitizerTest(.thread, expectedName: "thread")
    }

    func testUndefinedSanitizer() throws {
        try self.sanitizerTest(.undefined, expectedName: "undefined")
    }

    func testScudoSanitizer() throws {
        try self.sanitizerTest(.scudo, expectedName: "scudo")
    }

    func testSnippets() throws {
        let fs: FileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/Lib/Lib.swift",
            "/Pkg/Snippets/ASnippet.swift",
            "/Pkg/.build/release.yaml"
        )
        let buildPath = AbsolutePath("/Pkg/.build")
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Lib",
                    path: "/Pkg",
                    toolsVersion: .vNext,
                    dependencies: [],
                    products: [
                        ProductDescription(name: "Lib", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib", dependencies: [], type: .regular),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let plan = try mockBuildPlan(
            buildPath: buildPath,
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
        let swiftGetVersionFilePath = try XCTUnwrap(llbuild.swiftGetVersionFiles.first?.value)

        let yamlContents: String = try fs.readFileContents(yaml)
        let inputs: SerializedJSON = """
            inputs: ["\(AbsolutePath(
                "/Pkg/Snippets/ASnippet.swift"
            ))","\(swiftGetVersionFilePath)","\(AbsolutePath("/Pkg/.build/debug/Modules/Lib.swiftmodule"))"
        """
        XCTAssertMatch(yamlContents, .contains(inputs.underlying))
    }

    private func sanitizerTest(_ sanitizer: PackageModel.Sanitizer, expectedName: String) throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Sources/clib/clib.c",
            "/Pkg/Sources/clib/include/clib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib", "clib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(name: "clib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            // Unrealistic: we can't enable all of these at once on all platforms.
            // This test codifies current behavior, not ideal behavior, and
            // may need to be amended if we change it.
            targetSanitizers: EnabledSanitizers([sanitizer]),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(3)

        let exe = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        XCTAssertMatch(exe, ["-sanitize=\(expectedName)"])

        let lib = try result.moduleBuildDescription(for: "lib").swift().compileArguments()
        XCTAssertMatch(lib, ["-sanitize=\(expectedName)"])

        let clib = try result.moduleBuildDescription(for: "clib").clang().basicArguments(isCXX: false)
        XCTAssertMatch(clib, ["-fsanitize=\(expectedName)"])

        XCTAssertMatch(try result.buildProduct(for: "exe").linkArguments(), ["-sanitize=\(expectedName)"])
    }

    func testBuildParameterLTOMode() throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/cLib/cLib.c",
            "/Pkg/Sources/cLib/include/cLib.h"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["cLib"]),
                        TargetDescription(name: "cLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let toolchain = try UserToolchain.default
        let result = try BuildPlanResult(plan: mockBuildPlan(
            toolchain: toolchain,
            graph: graph,
            linkingParameters: .init(
                linkTimeOptimizationMode: .full
            ),
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        // Compile C Target
        let cLibCompileArguments = try result.moduleBuildDescription(for: "cLib").clang().basicArguments(isCXX: false)
        let cLibCompileArgumentsPattern: [StringPattern] = ["-flto=full"]
        XCTAssertMatch(cLibCompileArguments, cLibCompileArgumentsPattern)

        // Compile Swift Target
        let exeCompileArguments = try result.moduleBuildDescription(for: "exe").swift().compileArguments()
        let exeCompileArgumentsPattern: [StringPattern] = ["-lto=llvm-full"]
        XCTAssertMatch(exeCompileArguments, exeCompileArgumentsPattern)

        // Assert the objects built by the Swift Target are actually bitcode
        // files, indicated by the "bc" extension.
        let exeCompileObjects = try result.moduleBuildDescription(for: "exe").swift().objects
        XCTAssert(exeCompileObjects.allSatisfy { $0.extension == "bc" })

        // Assert the objects getting linked contain all the bitcode objects
        // built by the Swift Target
        let exeProduct = try result.buildProduct(for: "exe")
        for exeCompileObject in exeCompileObjects {
            XCTAssertTrue(exeProduct.objects.contains(exeCompileObject))
        }
    }

    func testPackageDependencySetsUserModuleVersion() throws {
        let fs = InMemoryFileSystem(emptyFiles: "/Pkg/Sources/exe/main.swift", "/ExtPkg/Sources/ExtLib/best.swift")

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    dependencies: [
                        .localSourceControl(path: "/ExtPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(name: "exe", dependencies: [
                            .product(name: "ExtPkg", package: "ExtPkg"),
                        ]),
                    ]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "ExtPkg",
                    path: "/ExtPkg",
                    version: "1.0.0",
                    toolsVersion: .v6_0,
                    products: [
                        ProductDescription(name: "ExtPkg", type: .library(.automatic), targets: ["ExtLib"]),
                    ],
                    targets: [
                        TargetDescription(name: "ExtLib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            environment: BuildEnvironment(
                platform: .linux,
                configuration: .release
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        switch try XCTUnwrap(
            result.targetMap[.init(
                moduleName: "ExtLib",
                packageIdentity: "ExtPkg",
                buildTriple: .destination
            )]
        ) {
        case .swift(let swiftTarget):
            if #available(macOS 13, *) { // `.contains` is only available in macOS 13 or newer
                XCTAssertTrue(try swiftTarget.compileArguments().contains(["-user-module-version", "1.0.0"]))
            }
        case .clang:
            XCTFail("expected a Swift target")
        }
    }

    func testBasicSwiftPackageWithoutLocalRpath() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldDisableLocalRpath: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))

        result.checkProductsCount(1)
        result.checkTargetsCount(2)

        let buildPath = result.plan.productsBuildPath

        #if os(macOS)
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-Xlinker", "-no_warn_duplicate_libraries",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-Xlinker", "-rpath", "-Xlinker", "/fake/path/lib/swift-5.5/macosx",
            "-target", defaultTargetTriple,
            "-Xlinker", "-add_ast_path",
            "-Xlinker", buildPath.appending(components: "Modules", "lib.swiftmodule").pathString,
            "-Xlinker", "-add_ast_path",
            "-Xlinker", buildPath.appending(components: "exe.build", "exe.swiftmodule").pathString,
            "-g",
        ]
        #elseif os(Windows)
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe.exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf",
        ]
        #else
        let linkArguments = [
            result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
            "-L", buildPath.pathString,
            "-o", buildPath.appending(components: "exe").pathString,
            "-module-name", "exe",
            "-emit-executable",
            "@\(buildPath.appending(components: "exe.product", "Objects.LinkFileList"))",
            "-target", defaultTargetTriple,
            "-g",
        ]
        #endif

        XCTAssertEqual(try result.buildProduct(for: "exe").linkArguments(), linkArguments)
        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    // testing of deriving dynamic libraries for explicitly linking rdar://108561857
    func testDerivingDylibs() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/thisPkg/Sources/exe/main.swift",
            "/fooPkg/Sources/FooLogging/file.swift",
            "/barPkg/Sources/BarLogging/file.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createFileSystemManifest(
                    displayName: "fooPkg",
                    path: "/fooPkg",
                    dependencies: [
                        .localSourceControl(path: "/barPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(name: "FooLogging", type: .library(.dynamic), targets: ["FooLogging"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "FooLogging",
                            dependencies: [.product(name: "BarLogging", package: "barPkg")]
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "barPkg",
                    path: "/barPkg",
                    products: [
                        ProductDescription(name: "BarLogging", type: .library(.dynamic), targets: ["BarLogging"]),
                    ],
                    targets: [
                        TargetDescription(name: "BarLogging", dependencies: []),
                    ]
                ),
                Manifest.createRootManifest(
                    displayName: "thisPkg",
                    path: "/thisPkg",
                    toolsVersion: .v5_8,
                    dependencies: [
                        .localSourceControl(path: "/fooPkg", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: [.product(name: "FooLogging", package: "fooPkg"),],
                            type: .executable
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let result = try BuildPlanResult(plan: mockBuildPlan(
            graph: graph,
            linkingParameters: .init(
                shouldLinkStaticSwiftStdlib: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        ))
        result.checkProductsCount(3)
        result.checkTargetsCount(3)
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "FooLogging" })
        XCTAssertTrue(result.targetMap.values.contains { $0.target.name == "BarLogging" })
        let buildProduct = try XCTUnwrap(
            result.productMap[.init(
                productName: "exe",
                packageIdentity: "thisPkg",
                buildTriple: .destination
            )]
        )
        let dylibs = Array(buildProduct.dylibs.map({$0.product.name})).sorted()
        XCTAssertEqual(dylibs, ["BarLogging", "FooLogging"])
    }

    func testSwiftPackageWithProvidedLibraries() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/A/Sources/ATarget/main.swift",
            "/Libraries/B/BTarget.swiftmodule",
            "/Libraries/C/CTarget.swiftmodule"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "A",
                    path: "/A",
                    dependencies: [
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/C", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    products: [
                        ProductDescription(
                            name: "A",
                            type: .executable,
                            targets: ["ATarget"]
                        )
                    ],
                    targets: [
                        TargetDescription(name: "ATarget", dependencies: ["BLibrary", "CLibrary"])
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "B",
                    path: "/B",
                    products: [
                        ProductDescription(name: "BLibrary", type: .library(.automatic), targets: ["BTarget"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "BTarget",
                            path: "/Libraries/B",
                            type: .providedLibrary
                        )
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "C",
                    path: "/C",
                    products: [
                        ProductDescription(name: "CLibrary", type: .library(.automatic), targets: ["CTarget"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "CTarget",
                            path: "/Libraries/C",
                            type: .providedLibrary
                        )
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try mockBuildPlan(
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let result = try BuildPlanResult(plan: plan)

        result.checkProductsCount(1)
        result.checkTargetsCount(1)

        XCTAssertMatch(
            try result.moduleBuildDescription(for: "ATarget").swift().compileArguments(),
            [
                .anySequence,
                "-I", "/Libraries/C",
                "-I", "/Libraries/B",
                .anySequence
            ]
        )

        let linkerArgs = try result.buildProduct(for: "A").linkArguments()

        XCTAssertMatch(
            linkerArgs,
            [
                .anySequence,
                "-L", "/Libraries/B",
                "-l", "BTarget",
                .anySequence
            ]
        )

        XCTAssertMatch(
            linkerArgs,
            [
                .anySequence,
                "-L", "/Libraries/C",
                "-l", "CTarget",
                .anySequence
            ]
        )
    }

    func testDefaultVersions() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/foo/foo.swift"
        )

        let expectedVersions = [
          ToolsVersion.v4: "4",
          ToolsVersion.v4_2: "4.2",
          ToolsVersion.v5: "5",
          ToolsVersion.v6_0: "6",
          ToolsVersion.vNext: "6"
        ]
        for (toolsVersion, expectedVersionString) in expectedVersions {
            let observability = ObservabilitySystem.makeForTesting()
            let graph = try loadModulesGraph(
              fileSystem: fs,
              manifests: [
                Manifest.createRootManifest(
                  displayName: "Pkg",
                  path: "/Pkg",
                  toolsVersion: toolsVersion,
                  targets: [
                    TargetDescription(
                      name: "foo"
                    ),
                  ]
                ),
              ],
              observabilityScope: observability.topScope
            )

            let result = try BuildPlanResult(plan: mockBuildPlan(
              graph: graph,
              fileSystem: fs,
              observabilityScope: observability.topScope
            ))

            XCTAssertMatch(
              try result.moduleBuildDescription(for: "foo").swift().compileArguments(),
              [
                "-swift-version", .equal(expectedVersionString)
              ]
            )
        }
    }
}
