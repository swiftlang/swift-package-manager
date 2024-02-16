//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Build
@testable import PackageModel

import Basics
import SPMTestSupport
import XCTest

import class TSCBasic.BufferedOutputByteStream
import class TSCBasic.InMemoryFileSystem

final class BuildOperationTests: XCTestCase {
    func testDetectUnexpressedDependencies() throws {
        let fs = InMemoryFileSystem(files: [
            "/path/to/build/debug/Lunch.build/Lunch.d" : "/Best.framework"
        ])

        let observability = ObservabilitySystem.makeForTesting()
        let buildOp = BuildOperation(
            productsBuildParameters: mockBuildParameters(shouldDisableLocalRpath: false),
            toolsBuildParameters: mockBuildParameters(shouldDisableLocalRpath: false),
            cacheBuildManifest: false,
            packageGraphLoader: { fatalError() },
            additionalFileRules: [],
            pkgConfigDirectories: [],
            dependenciesByRootPackageIdentity: [:],
            targetsByRootPackageIdentity: [:],
            outputStream: BufferedOutputByteStream(),
            logLevel: .info,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        buildOp.detectUnexpressedDependencies(
            availableLibraries: [
                .init(
                    identities: [
                        .sourceControl(url: .init("https://example.com/org/foo"))
                    ],
                    version: "1.0.0",
                    productName: "Best",
                    schemaVersion: 1
                )
            ],
            targetDependencyMap: ["Lunch": []]
        )

        XCTAssertEqual(
            observability.diagnostics.map { $0.message },
            ["target 'Lunch' has an unexpressed depedency on 'foo'"]
        )
    }

    func testReportedBuildTaskCountMonotonicallyIncreases() throws {
        try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { tmp in
            let productsBuildPath = tmp.appending("products-build")
            let toolsBuildPath = tmp.appending("tools-build")

            let mainSwift = tmp.appending(components: ["Pkg", "Sources", "exe", "main.swift"])
            try localFileSystem.writeFileContents(mainSwift, string: "")
            let clibC = tmp.appending(components: ["Pkg", "Sources", "cLib", "cLib.c",])
            try localFileSystem.writeFileContents(clibC, string: "")
            let clibH = tmp.appending(components: ["Pkg", "Sources", "cLib", "include", "cLib.h"])
            try localFileSystem.writeFileContents(clibH, string: "")

            let observability = ObservabilitySystem.makeForTesting()
            let buildOp = BuildOperation(
                productsBuildParameters: mockBuildParameters(buildPath: productsBuildPath),
                toolsBuildParameters: mockBuildParameters(buildPath: toolsBuildPath),
                cacheBuildManifest: false,
                packageGraphLoader: {
                    try loadPackageGraph(
                        fileSystem: localFileSystem,
                        manifests: [
                            Manifest.createRootManifest(
                                displayName: "Pkg",
                                path: "\(tmp.pathString)/Pkg",
                                targets: [
                                    TargetDescription(name: "exe", dependencies: ["cLib"]),
                                    TargetDescription(name: "cLib", dependencies: []),
                                ]
                            ),
                        ],
                        observabilityScope: observability.topScope
                    )
                },
                additionalFileRules: [],
                pkgConfigDirectories: [],
                dependenciesByRootPackageIdentity: [:],
                targetsByRootPackageIdentity: [:],
                outputStream: BufferedOutputByteStream(),
                logLevel: .info,
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope
            )
            try buildOp.build()
        }
    }
}
