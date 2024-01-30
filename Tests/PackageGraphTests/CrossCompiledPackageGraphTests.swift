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

import class Basics.ObservabilitySystem
import class PackageModel.Manifest
import struct PackageModel.ProductDescription
import struct PackageModel.TargetDescription
import func SPMTestSupport.loadPackageGraph
import func SPMTestSupport.PackageGraphTester
import func SPMTestSupport.XCTAssertNoDiagnostics
import class TSCBasic.InMemoryFileSystem

@testable
import PackageGraph

import XCTest

final class CrossCompiledPackageGraphTests: XCTestCase {
    func testMacros() throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/swift-firmware/Sources/Core/source.swift",
            "/swift-firmware/Sources/HAL/source.swift",
            "/swift-firmware/Tests/CoreTests/source.swift",
            "/swift-firmware/Tests/HALTests/source.swift",
            "/swift-mmio/Sources/MMIO/source.swift",
            "/swift-mmio/Sources/MMIOMacros/source.swift",
            "/swift-syntax/Sources/SwiftSyntax/source.swift",
            "/swift-syntax/Tests/SwiftSyntaxTests/source.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let g = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "swift-firmware",
                    path: "/swift-firmware",
                    dependencies: [
                        .localSourceControl(
                            path: "/swift-mmio",
                            requirement: .upToNextMajor(from: "1.0.0")
                        )
                    ],
                    products: [
                        ProductDescription(
                            name: "Core",
                            type: .executable,
                            targets: ["Core"]
                        )
                    ],
                    targets: [
                        TargetDescription(
                            name: "Core",
                            dependencies: ["HAL"],
                            type: .executable
                        ),
                        TargetDescription(
                            name: "HAL",
                            dependencies: [.product(name: "MMIO", package: "swift-mmio")]
                        ),
                        TargetDescription(name: "CoreTests", dependencies: ["Core"], type: .test),
                        TargetDescription(name: "HALTests", dependencies: ["HAL"], type: .test),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "swift-mmio",
                    path: "/swift-mmio",
                    dependencies: [
                        .localSourceControl(
                            path: "/swift-syntax",
                            requirement: .upToNextMajor(from: "1.0.0")
                        )
                    ],
                    products: [
                        ProductDescription(
                            name: "MMIO",
                            type: .library(.automatic),
                            targets: ["MMIO"]
                        )
                    ],
                    targets: [
                        TargetDescription(
                            name: "MMIO",
                            dependencies: [.target(name: "MMIOMacros")]
                        ),
                        TargetDescription(
                            name: "MMIOMacros",
                            dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax")],
                            type: .macro
                        )
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "swift-syntax",
                    path: "/swift-syntax",
                    products: [
                        ProductDescription(
                            name: "SwiftSyntax",
                            type: .library(.automatic),
                            targets: ["SwiftSyntax"]
                        )
                    ],
                    targets: [
                        TargetDescription(name: "SwiftSyntax", dependencies: []),
                        TargetDescription(name: "SwiftSyntaxTests", dependencies: ["SwiftSyntax"], type: .test),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(g) { result in
            result.check(packages: "swift-firmware", "swift-mmio", "swift-syntax")
            result.check(targets: "Core", "HAL", "MMIO", "MMIOMacros", "SwiftSyntax")
            result.check(testModules: "CoreTests", "HALTests")
            result.checkTarget("Core") { result in
                result.check(buildTriple: .destination)
                result.check(dependencies: "HAL")
            }
            result.checkTarget("HAL") { result in
                result.check(buildTriple: .destination)
                result.check(dependencies: "MMIO")
            }
            result.checkTarget("MMIO") { result in
                result.check(buildTriple: .destination)
                result.check(dependencies: "MMIOMacros")
            }
            result.checkTarget("MMIOMacros") { result in
                result.check(buildTriple: .tools)
                result.checkDependency("SwiftSyntax") { result in
                    result.checkProduct { result in
                        result.check(buildTriple: .tools)
                        result.checkTarget("SwiftSyntax") { result in
                            result.check(buildTriple: .tools)
                        }
                    }
                }
            }
        }
    }
}
