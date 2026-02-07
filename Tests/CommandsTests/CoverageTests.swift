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
        .Feature.CommandLineArguments.EnableCodeCoverage
    )
)
struct CoverageTests {
    @Test(
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9600", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func executingTestsWithCoverageWithoutCodeBuiltWithCoverageGeneratesAFailure(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { path in
            _ = try await executeSwiftBuild(
                path,
                configuration: config,
                extraArgs: ["--build-tests"],
                buildSystem: buildSystem,
            )
            try await withKnownIssue(isIntermittent: true) {
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
            } when: {
                ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
            }
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9588", relationship: .defect),
        .tags(
            .Feature.Command.Test,
            .Feature.CommandLineArguments.BuildTests,
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
            let codeCovPathString = try await getCoveragePath(
                path,
                with: BuildData(buildSystem: buildSystem, config: config),
            )

            let codeCovPath = try AbsolutePath(validating: codeCovPathString)

            // WHEN we build with coverage enabled
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
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild // This was no longer an issue when I tested at-desk
        }
    }

    @Test(
        .tags(
            .Feature.Command.Test,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/9588", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms, [
            "Coverage/Simple",
            "Miscellaneous/TestDiscovery/Simple",
        ],
    )
    func generateCoverageReport(
        buildSystem: BuildSystemProvider.Kind,
        fixtureName: String
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: fixtureName) { path in
            let coveragePathString = try await getCoveragePath(
                path,
                with: BuildData(buildSystem: buildSystem, config: config),
            )
            let coveragePath = try AbsolutePath(validating: coveragePathString)
            try #require(!localFileSystem.exists(coveragePath))

            // WHEN we test with coverage enabled
            try await withKnownIssue(isIntermittent: true) {
                try await executeSwiftTest(
                    path,
                    configuration: config,
                    extraArgs: [
                        "--enable-code-coverage",
                    ],
                    throwIfCommandFails: true,
                    buildSystem: buildSystem,
                )

                // THEN we expect the file to exists
                #expect(localFileSystem.exists(coveragePath))
            } when: {
                (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)
            }
        }
    }

}
