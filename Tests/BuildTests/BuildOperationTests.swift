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
@_spi(SwiftPMInternal)
import _InternalTestSupport
import XCTest

import class TSCBasic.BufferedOutputByteStream

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
        outputStream: BufferedOutputByteStream(),
        logLevel: .info,
        fileSystem: fs,
        observabilityScope: observabilityScope
    )
}

final class BuildOperationTests: XCTestCase {
    func testDetectProductTripleChange() async throws {
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
                    ],
                    traits: []
                ),
            ],
            observabilityScope: observability.topScope
        )
        try await withTemporaryDirectory { tmpDir in
            let scratchDirectory = tmpDir.appending(".build")
            let fs = localFileSystem
            let triples = try [Triple("x86_64-unknown-linux-gnu"), Triple("wasm32-unknown-wasi")]
            var llbuildManifestByTriple: [String: String] = [:]

            // Perform initial builds for each triple
            for triple in triples {
                let targetBuildParameters = mockBuildParameters(
                    destination: .target,
                    buildPath: scratchDirectory.appending(triple.tripleString),
                    config: .debug,
                    triple: triple
                )
                let buildOp = mockBuildOperation(
                    productsBuildParameters: targetBuildParameters,
                    toolsBuildParameters: mockBuildParameters(destination: .host),
                    cacheBuildManifest: false,
                    packageGraphLoader: { packageGraph },
                    scratchDirectory: scratchDirectory,
                    fs: fs, observabilityScope: observability.topScope
                )
                // Generate initial llbuild manifest
                let _ = try await buildOp.getBuildDescription()
                // Record the initial llbuild manifest as expected one
                llbuildManifestByTriple[triple.tripleString] = try fs.readFileContents(targetBuildParameters.llbuildManifest)
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
                    let targetBuildParameters = mockBuildParameters(
                        destination: .target,
                        buildPath: scratchDirectory.appending(triple.tripleString),
                        config: .debug,
                        triple: triple
                    )
                    let buildOp = mockBuildOperation(
                        productsBuildParameters: targetBuildParameters,
                        toolsBuildParameters: mockBuildParameters(destination: .host),
                        cacheBuildManifest: true,
                        packageGraphLoader: { packageGraph },
                        scratchDirectory: scratchDirectory,
                        fs: fs, observabilityScope: observability.topScope
                    )
                    // Generate llbuild manifest
                    let _ = try await buildOp.getBuildDescription()

                    // Ensure that llbuild manifest is updated to the expected one
                    let actualManifest: String = try fs.readFileContents(targetBuildParameters.llbuildManifest)
                    let expectedManifest = try XCTUnwrap(llbuildManifestByTriple[triple.tripleString])
                    XCTAssertEqual(actualManifest, expectedManifest)
                }
            }
        }
    }

    func testHostProductsAndTargetsWithoutExplicitDestination() async throws {
        let mock  = try macrosTestsPackageGraph()

        let hostParameters = mockBuildParameters(destination: .host)
        let targetParameters = mockBuildParameters(destination: .target)
        let op = mockBuildOperation(
            productsBuildParameters: targetParameters,
            toolsBuildParameters: hostParameters,
            packageGraphLoader: { mock.graph },
            scratchDirectory: AbsolutePath("/.build/\(hostTriple)"),
            fs: mock.fileSystem,
            observabilityScope: mock.observabilityScope
        )

        let mmioMacrosProductName = try await op.computeLLBuildTargetName(for: .product("MMIOMacros"))
        XCTAssertEqual(
            "MMIOMacros-\(hostTriple)-debug-tool.exe",
            mmioMacrosProductName
        )

        let mmioTestsProductName = try await op.computeLLBuildTargetName(
            for: .product("swift-mmioPackageTests")
        )
        XCTAssertEqual(
            "swift-mmioPackageTests-\(hostTriple)-debug-tool.test",
            mmioTestsProductName
        )

        let swiftSyntaxTestsProductName = try await op.computeLLBuildTargetName(
            for: .product("swift-syntaxPackageTests")
        )
        XCTAssertEqual(
            "swift-syntaxPackageTests-\(targetParameters.triple)-debug.test",
            swiftSyntaxTestsProductName
        )

        for target in ["MMIOMacros", "MMIOPlugin", "MMIOMacrosTests", "MMIOMacro+PluginTests"] {
            let targetName = try await op.computeLLBuildTargetName(for: .target(target))
            XCTAssertEqual(
                "\(target)-\(hostTriple)-debug-tool.module",
                targetName
            )
        }

        let swiftSyntaxTestsTarget = try await op.computeLLBuildTargetName(
            for: .target("SwiftSyntaxTests")
        )
        XCTAssertEqual(
            "SwiftSyntaxTests-\(targetParameters.triple)-debug.module",
            swiftSyntaxTestsTarget
        )

        let dependencies = try BuildSubset.target("MMIOMacro+PluginTests").recursiveDependencies(
            for: mock.graph,
            observabilityScope: mock.observabilityScope
        )

        XCTAssertNotNil(dependencies)
        XCTAssertTrue(dependencies!.count > 0)
    }
}
