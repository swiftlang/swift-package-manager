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
import LLBuildManifest
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph
import SPMBuildCore
import SPMTestSupport
import XCTest

import class TSCBasic.BufferedOutputByteStream
import class TSCBasic.InMemoryFileSystem

private func mockBuildOperation(
    productsBuildParameters: BuildParameters,
    toolsBuildParameters: BuildParameters,
    cacheBuildManifest: Bool = false,
    packageGraphLoader: @escaping () -> ModulesGraph = { fatalError() },
    scratchDirectory: AbsolutePath,
    fs: any Basics.FileSystem,
    observabilityScope: ObservabilityScope
) -> BuildOperation {
    return BuildOperation(
        productsBuildParameters: productsBuildParameters,
        toolsBuildParameters: toolsBuildParameters,
        cacheBuildManifest: cacheBuildManifest,
        packageGraphLoader: packageGraphLoader,
        scratchDirectory: scratchDirectory,
        additionalFileRules: [],
        pkgConfigDirectories: [],
        dependenciesByRootPackageIdentity: [:],
        targetsByRootPackageIdentity: [:],
        outputStream: BufferedOutputByteStream(),
        logLevel: .info,
        fileSystem: fs,
        observabilityScope: observabilityScope
    )
}

final class BuildOperationTests: XCTestCase {
    func testDetectUnexpressedDependencies() throws {
        let scratchDirectory = AbsolutePath("/path/to/build")
        let triple = hostTriple
        let buildParameters = mockBuildParameters(
            buildPath: scratchDirectory.appending(triple.tripleString),
            shouldDisableLocalRpath: false,
            triple: triple
        )

        let fs = InMemoryFileSystem(files: [
            "\(buildParameters.dataPath)/debug/Lunch.build/Lunch.d" : "/Best.framework"
        ])

        let observability = ObservabilitySystem.makeForTesting()
        let buildOp = mockBuildOperation(
            productsBuildParameters: buildParameters,
            toolsBuildParameters: buildParameters,
            scratchDirectory: scratchDirectory,
            fs: fs, observabilityScope: observability.topScope
        )
        buildOp.detectUnexpressedDependencies(
            availableLibraries: [
                .init(
                    location: "/foo",
                    metadata: .init(
                        identities: [
                            .sourceControl(url: .init("https://example.com/org/foo"))
                        ],
                        version: "1.0.0",
                        productName: "Best",
                        schemaVersion: 1
                    )
                )
            ],
            targetDependencyMap: ["Lunch": []]
        )

        XCTAssertEqual(
            observability.diagnostics.map { $0.message },
            ["target 'Lunch' has an unexpressed depedency on 'foo'"]
        )
    }

    func testDetectProductTripleChange() throws {
        let observability = ObservabilitySystem.makeForTesting()
        let fs = InMemoryFileSystem(
            emptyFiles: "/Pkg/Sources/ATarget/foo.swift"
        )
        let packageGraph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createRootManifest(
                    displayName: "SwitchTriple",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "ATarget"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        try withTemporaryDirectory { tmpDir in
            let scratchDirectory = tmpDir.appending(".build")
            let fs = localFileSystem
            let triples = try [Triple("x86_64-unknown-linux-gnu"), Triple("wasm32-unknown-wasi")]
            var llbuildManifestByTriple: [String: String] = [:]

            // Perform initial builds for each triple
            for triple in triples {
                let buildParameters = mockBuildParameters(
                    buildPath: scratchDirectory.appending(triple.tripleString),
                    config: .debug,
                    triple: triple
                )
                let buildOp = mockBuildOperation(
                    productsBuildParameters: buildParameters,
                    toolsBuildParameters: buildParameters,
                    cacheBuildManifest: false,
                    packageGraphLoader: { packageGraph },
                    scratchDirectory: scratchDirectory,
                    fs: fs, observabilityScope: observability.topScope
                )
                // Generate initial llbuild manifest
                let _ = try buildOp.getBuildDescription()
                // Record the initial llbuild manifest as expected one
                llbuildManifestByTriple[triple.tripleString] = try fs.readFileContents(buildParameters.llbuildManifest)
            }

            XCTAssertTrue(fs.exists(scratchDirectory.appending("debug.yaml")))
            // FIXME: There should be a build database with manifest cache after the initial build.
            // The initial build usually triggered with `cacheBuildManifest=false` because llbuild
            // manifest file and description.json are not found. However, with `cacheBuildManifest=false`,
            // `BuildOperation` does not trigger "PackageStructure" build, thus the initial build does
            // not record the manifest cache. So "getBuildDescription" doesn't create build.db for the
            // initial planning and the second build always need full-planning.
            //
            // XCTAssertTrue(fs.exists(scratchDirectory.appending("build.db")))

            // Perform incremental build several times and switch triple for each time
            for _ in 0..<4 {
                for triple in triples {
                    let buildParameters = mockBuildParameters(
                        buildPath: scratchDirectory.appending(triple.tripleString),
                        config: .debug,
                        triple: triple
                    )
                    let buildOp = mockBuildOperation(
                        productsBuildParameters: buildParameters,
                        toolsBuildParameters: buildParameters,
                        cacheBuildManifest: true,
                        packageGraphLoader: { packageGraph },
                        scratchDirectory: scratchDirectory,
                        fs: fs, observabilityScope: observability.topScope
                    )
                    // Generate llbuild manifest
                    let _ = try buildOp.getBuildDescription()

                    // Ensure that llbuild manifest is updated to the expected one
                    let actualManifest: String = try fs.readFileContents(buildParameters.llbuildManifest)
                    let expectedManifest = try XCTUnwrap(llbuildManifestByTriple[triple.tripleString])
                    XCTAssertEqual(actualManifest, expectedManifest)
                }
            }
        }
    }
}
