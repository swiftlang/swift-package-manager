//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import _InternalBuildTestSupport
import _InternalTestSupport
import XCTest

/// Test suite for Native only tests.
/// TODO: Almost all the BuildPlanTests are native only and should be cleaned up.
class NativeBuildPlanTests: XCTestCase {
    func testMixedSource() async throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Pkg/Sources/lib/file1.swift",
                "/Pkg/Sources/lib/file2.c"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "lib"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        await XCTAssertAsyncThrowsError(try await mockBuildPlan(graph: graph, fileSystem: fs, observabilityScope: observability.topScope)) { error in
            XCTAssertEqual(error.localizedDescription, "lib: mixed language source files in Swift targets are not supported by the native build system.")
        }
    }
}
