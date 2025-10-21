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

import Foundation
import Commands
import _InternalTestSupport
import var Basics.localFileSystem
import struct Basics.AbsolutePath
import enum PackageModel.BuildConfiguration
import struct SPMBuildCore.BuildSystemProvider
import Testing

@Suite(
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.CodeCoverage,
    )
)
struct CoverageTests {
    @Test(
        .SWBINTTODO("Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."),
        .tags(
            Tag.Feature.CodeCoverage,
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executingTestsWithCoverageWithoutCodeBuiltWithCoverageGeneratesAFailure(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: (ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild)) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
                _ = try await executeSwiftBuild(
                    path,
                    configuration: config,
                    extraArgs: ["--build-tests"],
                    buildSystem: buildSystem,
                )
                await #expect(throws: (any Error).self ) {
                    try await executeSwiftTest(
                        path,
                        configuration: config,
                        extraArgs: [
                            "--skip-build",
                            "--enable-code-coverage",
                        ],
                        throwIfCommandFails: true,
                        buildSystem: buildSystem,
                    )
                }
            }
        } when: {
            buildSystem == .swiftbuild && [.linux, .windows].contains(ProcessInfo.hostOperatingSystem)
        }
    }

    @Test(
        .SWBINTTODO("Test failed because of missing plugin support in the PIF builder. This can be reinvestigated after the support is there."),
        .IssueWindowsCannotSaveAttachment,
        .tags(
            Tag.Feature.CodeCoverage,
            Tag.Feature.Command.Test,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executingTestsWithCoverageWithCodeBuiltWithCoverageGeneratesCodeCoverage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        // Test that enabling code coverage during building produces the expected folder.
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
            let codeCovPathString = try await executeSwiftTest(
                path,
                configuration: config,
                extraArgs: [
                    "--show-coverage-path",
                ],
                throwIfCommandFails: true,
                buildSystem: buildSystem,
            ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            let codeCovPath = try AbsolutePath(validating: codeCovPathString)

            // WHEN we build with coverage enabled
            try await withKnownIssue {
                try await executeSwiftBuild(
                    path,
                    configuration: config,
                    extraArgs: ["--build-tests", "--enable-code-coverage"],
                    buildSystem: buildSystem,
                )

                // AND we test with coverag enabled and skip the build
                try await executeSwiftTest(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--skip-build",
                        "--enable-code-coverage",
                    ],
                    buildSystem: buildSystem,
                )

                // THEN we expect the file to exists
                expectFileExists(at: codeCovPath)

                // AND the parent directory is non empty
                let codeCovFiles = try localFileSystem.getDirectoryContents(codeCovPath.parentDirectory)
                #expect(codeCovFiles.count > 0)
            } when: {
                ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild
            }
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms), [
            "Coverage/Simple",
            "Miscellaneous/TestDiscovery/Simple",
        ],
    )
    func generateCoverageReport(
        buildData: BuildData,
        fixtureName: String
    ) async throws {
        try await fixture(name: fixtureName) { path in
            let coveragePathString = try await executeSwiftTest(
                path,
                configuration: buildData.config,
                extraArgs: [
                    "--show-coverage-path",
                ],
                throwIfCommandFails: true,
                buildSystem: buildData.buildSystem,
            ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let coveragePath = try AbsolutePath(validating: coveragePathString)
            try #require(!localFileSystem.exists(coveragePath))

            // WHEN we test with coverage enabled
            try await withKnownIssue {
                try await executeSwiftTest(
                    path,
                    configuration: buildData.config,
                    extraArgs: [
                        "--enable-code-coverage",
                    ],
                    throwIfCommandFails: true,
                    buildSystem: buildData.buildSystem,
                )

                // THEN we expect the file to exists
                #expect(localFileSystem.exists(coveragePath))
            } when: {
                (buildData.buildSystem == .swiftbuild && [.windows, .linux].contains(ProcessInfo.hostOperatingSystem))
            }
        }
    }
}
