//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import struct SPMBuildCore.BuildSystemProvider
import PackageModel
import _InternalTestSupport
import Testing

import var TSCBasic.localFileSystem

@Suite(
    .tags(
        .TestSize.large,
    )
)
struct BuildSystemDelegateTests {
    @Test(
        .requiresSDKDependentTestsSupport,
        .requireHostOS(.macOS),  // These linker diagnostics are only produced on macOS.
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func doNotFilterLinkerDiagnostics(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/DoNotFilterLinkerDiagnostics") { fixturePath in
            let (stdout, stderr) = try await executeSwiftBuild(
                fixturePath,
                buildSystem: buildSystem,
            )
            switch buildSystem {
            case .native:
                #expect(
                    stdout.contains("ld: warning: search path 'foobar' not found"),
                    "log didn't contain expected linker diagnostics.  stderr: '\(stderr)')",
                )
            case .swiftbuild:
                #expect(
                    stderr.contains("ld: warning: search path 'foobar' not found"),
                    "log didn't contain expected linker diagnostics. stderr: '\(stderr)",
                )
                #expect(
                    !stdout.contains("ld: warning: search path 'foobar' not found"),
                    "log didn't contain expected linker diagnostics.  stderr: '\(stderr)')",
                )
            case .xcode:
                Issue.record("Test expectation has not be implemented")
            }
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8540", relationship: .defect),  // Package fails to build when the test is being executed"
        .requiresSDKDependentTestsSupport,
        .tags(
            .Feature.Command.Build,
            .Feature.TargetType.Executable,
            .Feature.TargetType.Library,
            .Feature.CommandLineArguments.BuildSystem,
            .Feature.CommandLineArguments.Configuration,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func filterNonFatalCodesignMessages(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            // Note: we can re-use the `TestableExe` fixture here since we just need an executable.
            try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
                _ = try await executeSwiftBuild(
                    fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
                let execPath = try fixturePath.appending(
                    components: buildSystem.binPath(for: config) + [executableName("TestableExe1")]
                )
                expectFileExists(at: execPath)
                try localFileSystem.removeFileTree(execPath)
                let (stdout, stderr) = try await executeSwiftBuild(
                    fixturePath,
                    configuration: config,
                    buildSystem: buildSystem,
                )
                #expect(!stdout.contains("replacing existing signature"), "log contained non-fatal codesigning messages stderr: '\(stderr)'")
                #expect(!stderr.contains("replacing existing signature"), "log contained non-fatal codesigning messages. stdout: '\(stdout)'")
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }
}
