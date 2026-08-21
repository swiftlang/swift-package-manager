//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import Testing
import _InternalTestSupport

/// Verifies that PIF generation is deterministic across every fixture in the repo.
@Suite(
    .serialized,
    .tags(.TestSize.large),
    .disabled("Disabled by default because these are very expensive to run")
)
struct PIFDeterminismTests {
    static let regenerationCount = 5

    static let fixturePackages: [String] = {
        let fixturesDir = AbsolutePath("../../../Fixtures", relativeTo: #filePath)
        var roots: [String] = []

        func walk(_ dir: AbsolutePath) {
            guard let contents = try? localFileSystem.getDirectoryContents(dir).sorted() else {
                return
            }

            if contents.contains("Package.swift") {
                roots.append(dir.relative(to: fixturesDir).pathString)
                return
            }

            for entry in contents {
                let child = dir.appending(component: entry)
                if localFileSystem.isDirectory(child), !localFileSystem.isSymlink(child) {
                    walk(child)
                }
            }
        }

        walk(fixturesDir)
        // This fixture has unicode in the path which crashes the Swift Testing harness
        return roots.filter { !$0.hasPrefix("Miscellaneous/UnicodeDependency") }
    }()

    @Test(arguments: fixturePackages)
    func pifGenerationIsDeterministic(fixtureName: String) async throws {
        try await fixture(name: fixtureName) { fixturePath in
            var dumps: [String] = []

            for run in 0 ..< Self.regenerationCount {
                let result: (stdout: String, stderr: String)
                do {
                    result = try await executeSwiftPackage(
                        fixturePath,
                        extraArgs: ["--manifest-cache", "local", "dump-pif"],
                        buildSystem: .swiftbuild,
                    )
                } catch {
                    if run == 0 {
                        // Skip fixtures which are intentionally broken packages.
                        return
                    }
                    throw error
                }
                dumps.append(result.stdout)
            }

            for (index, dump) in dumps.enumerated().dropFirst() where dump != dumps[0] {
                let firstDifference = zip(
                    dumps[0].split(separator: "\n", omittingEmptySubsequences: false),
                    dump.split(separator: "\n", omittingEmptySubsequences: false)
                ).first { $0 != $1 }

                Issue.record("""
                    PIF for fixture '\(fixtureName)' is not deterministic: run \(index + 1) of \
                    \(Self.regenerationCount) differs from run 1.
                    First differing line:
                      run 1: \(firstDifference?.0 ?? "<none>")
                      run \(index + 1): \(firstDifference?.1 ?? "<none>")
                    """)
                break
            }
        }
    }
}

// MARK: - Targeted determinism regressions
//
// The suite above is a broad net: it dumps the PIF for every fixture in the repo and
// diffs repeated runs. It catches anything, but it is disabled by default because it
// shells out and is far too slow for CI.
//
// The suite below complements it with fast, always-on assertions that name a specific
// defect and pin the exact expected output. Everything it needs is declared here so the
// two can evolve independently.

import PackageLoading
import SwiftBuild
import SwiftBuildSupport

@testable import SPMBuildCore

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) @testable import PackageGraph
@_spi(SwiftPMInternal) @testable import PackageModel

/// Regression tests for individual sources of non-deterministic PIF generation.
///
/// SwiftPM seeds its hash function per process, so iterating a `Set` or `Dictionary` and
/// appending the results to an ordered structure yields a different order on every
/// invocation. When that structure reaches the PIF, an unchanged package produces a
/// different build description each time: swift-build reads the `signature` fields written
/// by `PIF.sign(workspace:)` straight out of the JSON and folds them into the
/// `BuildDescriptionSignature` it uses as its on-disk cache key.
///
/// PR #10344 fixed one instance of this in trait-derived settings, and #10345 fixed header
/// ordering. See rdar://183168076.
///
/// Each test asserts an exact expected order rather than merely "stable across N runs".
/// A stability-only assertion would pass by luck whenever a single process happened to
/// produce a consistent order, and would not pin down *which* order is correct.
@Suite(
    .tags(
        .TestSize.medium,
        .FunctionalArea.PIF
    )
)
struct PIFOrderingTests {
    // MARK: - Linker flag ordering

    /// The linker-setting declarations a manifest can express that all collapse into the
    /// single PIF setting `OTHER_LDFLAGS`, paired with the flags each contributes.
    ///
    /// **Listed in the expected output order**, which is the contributing declarations
    /// sorted by name: LINK_FRAMEWORKS, LINK_LIBRARIES, OTHER_LDFLAGS. Expectations below
    /// are derived from this ordering rather than restated, so changing the intended sort
    /// means editing one list.
    private static let linkerContributions: [(declaration: String, setting: TargetBuildSettingDescription.Kind, flags: [String])] = [
        (declaration: "LINK_FRAMEWORKS", setting: .linkedFramework("Foundation"), flags: ["-framework", "Foundation"]),
        (declaration: "LINK_LIBRARIES", setting: .linkedLibrary("z"), flags: ["-lz"]),
        (declaration: "OTHER_LDFLAGS", setting: .unsafeFlags(["-Wl,-U,_undefined"]), flags: ["-Wl,-U,_undefined"]),
    ]

    /// `LINK_LIBRARIES`, `LINK_FRAMEWORKS` and `OTHER_LDFLAGS` are three distinct SwiftPM
    /// declarations that all map onto the single PIF setting `OTHER_LDFLAGS`.
    /// `computeAllBuildSettings` iterates the `[Declaration: [Assignment]]` dictionary and
    /// appends each group to a shared array, so the dictionary's iteration order becomes
    /// the linker argument order.
    ///
    /// This is the only defect in this suite that changes build *semantics* rather than
    /// only the cache key: linker argument order governs static archive resolution and
    /// duplicate-symbol precedence, so a package can link differently between two builds
    /// of identical sources.
    @Test
    func linkerFlagsFromDistinctDeclarationsAreOrderedDeterministically() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let (pif, expectations) = try await constructPIFForLinkerSettings(
            observability: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics)

        for expectation in expectations {
            let flags = try otherLDFlags(in: pif, forModuleNamed: expectation.moduleName)
            let contributed = flags.filter { $0 != "$(inherited)" }
            #expect(
                contributed == expectation.flags,
                "target \(expectation.moduleName) emitted linker flags out of order"
            )
        }
    }

    // MARK: - Fixtures

    /// Builds a PIF containing one target per multi-element subset of `linkerContributions`.
    ///
    /// Several targets rather than one is deliberate. Swift fixes its hash seed per
    /// *process*, so a single target samples exactly one dictionary iteration order per
    /// run and passes by luck whenever that order happens to be the sorted one — measured
    /// at 3 false passes in 12 runs against the unfixed code. Each subset presents a
    /// differently shaped dictionary, so the targets sample several independent orderings
    /// within one process and the test only passes if every one comes out sorted. That
    /// drops the false-pass rate to roughly 1 in 20.
    ///
    /// The residual flakiness is one-directional and therefore safe: against the *fixed*
    /// code this test passed 20 of 20 runs, so it will not fail spuriously in CI. It can
    /// only ever under-report the bug, never invent one.
    private func constructPIFForLinkerSettings(
        observability: ObservabilityScope
    ) async throws -> (pif: SwiftBuildSupport.PIF.TopLevelObject, expectations: [(moduleName: String, flags: [String])]) {
        let subsets = Self.linkerContributions.indices
            .reduce(into: [[Int]]()) { subsets, index in
                subsets = subsets + subsets.map { $0 + [index] } + [[index]]
            }
            .filter { $0.count > 1 }

        var targets: [TargetDescription] = []
        var expectations: [(moduleName: String, flags: [String])] = []
        var sourceFiles: [String] = []

        for subset in subsets {
            let moduleName = "Link\(subset.map(String.init).joined())"
            sourceFiles.append("/MyPkg/Sources/\(moduleName)/lib.swift")
            targets.append(
                try TargetDescription(
                    name: moduleName,
                    settings: subset.map { .init(tool: .linker, kind: Self.linkerContributions[$0].setting) }
                )
            )
            // The correct output order is the contributions sorted by declaration name,
            // which is the order `linkerContributions` is written in.
            expectations.append(
                (moduleName, subset.sorted().flatMap { Self.linkerContributions[$0].flags })
            )
        }

        let fs = InMemoryFileSystem(emptyFiles: sourceFiles)
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createRootManifest(
                    displayName: "MyPkg",
                    path: "/MyPkg",
                    toolsVersion: .v5_9,
                    products: try targets.map {
                        try .init(name: $0.name, type: .library(.automatic), targets: [$0.name])
                    },
                    targets: targets
                )
            ],
            observabilityScope: observability
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root,
                addLocalRpaths: .always
            ),
            fileSystem: fs,
            observabilityScope: observability
        )

        let buildParameters = mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        let pif = try await pifBuilder.constructPIF(
            buildParameters: buildParameters,
            hostBuildParameters: buildParameters
        ).0

        return (pif, expectations)
    }

    // MARK: - Helpers

    /// Looks up a module target by name. A library product also yields a `-dynamic`
    /// variant carrying the same name, so match on the canonical `PACKAGE-TARGET:<name>`
    /// id rather than the name alone.
    private func module(
        named name: String,
        in pif: SwiftBuildSupport.PIF.TopLevelObject
    ) throws -> ProjectModel.BaseTarget {
        let project = try #require(
            pif.workspace.projects.filter { $0.underlying.name == "MyPkg" }.only,
            "expected exactly one MyPkg project"
        )
        return try #require(
            project.underlying.targets.filter { $0.common.id.value == "PACKAGE-TARGET:\(name)" }.only,
            "expected exactly one target with id PACKAGE-TARGET:\(name)"
        )
    }

    private func otherLDFlags(
        in pif: SwiftBuildSupport.PIF.TopLevelObject,
        forModuleNamed name: String
    ) throws -> [String] {
        let target = try module(named: name, in: pif)
        let config = try #require(
            target.common.buildConfigs.first { $0.name == "Debug" },
            "expected a Debug build configuration"
        )
        return config.settings[.OTHER_LDFLAGS] ?? []
    }
}
