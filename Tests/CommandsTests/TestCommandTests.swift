//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import Basics
import Commands
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import PackageModel
import _InternalTestSupport
import TSCTestSupport
import Testing

@Suite(
    .serialized,  // to limit the number of swift executable running.
    .tags(
        Tag.TestSize.large,
        Tag.Feature.Command.Test,
    )
)
struct TestCommandTests {

    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        configuration: BuildConfiguration = .debug,
        buildSystem: BuildSystemProvider.Kind,
        throwIfCommandFails: Bool = true
    ) async throws -> (stdout: String, stderr: String) {
        try await executeSwiftTest(
            packagePath,
            configuration: configuration,
            extraArgs: args,
            throwIfCommandFails: throwIfCommandFails,
            buildSystem: buildSystem,
        )
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func usage(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        let stdout = try await execute(
            ["-help"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        #expect(stdout.contains("USAGE: swift test"), "got stdout:\n\(stdout)")
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func experimentalXunitMessageFailureArgumentIsHidden(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        let stdout = try await execute(
            ["--help"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        #expect(
            !stdout.contains("--experimental-xunit-message-failure"),
            "got stdout:\n\(stdout)",
        )
        #expect(
            !stdout.contains("When Set, enabled an experimental message failure content (XCTest only)."),
            "got stdout:\n\(stdout)",
        )
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func seeAlso(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        let stdout = try await execute(
            ["--help"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        #expect(stdout.contains("SEE ALSO: swift build, swift run, swift package"), "got stdout:\n\(stdout)")
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func version(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        let stdout = try await execute(
            ["--version"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        let versionRegex = try Regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#)
        #expect(stdout.contains(versionRegex))
    }

    @Test(
        .SWBINTTODO("Windows: Driver threw unable to load output file map"),
        .tags(
            .Feature.CommandLineArguments.Toolset,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func toolsetRunner(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {

        let configuration = BuildConfiguration.debug
        try await withKnownIssue(
            "Windows: Driver threw unable to load output file map",
            isIntermittent: true
        ) {
            try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
                #if os(Windows)
                    let win32 = ".win32"
                #else
                    let win32 = ""
                #endif
                let (stdout, stderr) = try await execute(
                    [
                        "--toolset",
                        fixturePath.appending("toolset\(win32).json").pathString,
                    ],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // We only expect tool's output on the stdout stream.
                #expect(stdout.contains("sentinel"))
                #expect(stdout.contains("\(fixturePath)"))

                // swift-build-tool output should go to stderr.
                withKnownIssue {
                    #expect(stderr.contains("Compiling"))
                } when: {
                    buildSystem == .swiftbuild // && ProcessInfo.hostOperatingSystem != .macOS
                }

                withKnownIssue {
                    #expect(stderr.contains("Linking"))
                } when: {
                    buildSystem == .swiftbuild // && ProcessInfo.hostOperatingSystem != .macOS
                }
            }
        } when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows)
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSmokeTestPipeline)
            || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline) // error: SwiftCompile normal x86_64 /tmp/Miscellaneous_EchoExecutable.sxkNTX/Miscellaneous_EchoExecutable/.build/x86_64-unknown-linux-gnu/Intermediates.noindex/EchoExecutable.build/Debug-linux/TestSuite-test-runner.build/DerivedSources/test_entry_point.swift failed with a nonzero exit code
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func numWorkersParallelRequirement(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self) {
                try await execute(
                    ["--num-workers", "1"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
            guard case let SwiftPMError.executionFailure(_, stdout, stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }

            #expect(
                stderr.contains("error: --num-workers must be used with --parallel"),
                "got stdout: \(stdout), stderr: \(stderr)",
            )
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func numWorkersValueSetToZeroRaisesAnError(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self) {
                try await execute(
                    ["--parallel", "--num-workers", "0"],
                    configuration: configuration,
                    buildSystem: buildSystem,
                    throwIfCommandFails: true,
                )
            }
            guard case let SwiftPMError.executionFailure(_, stdout, stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(
                stderr.contains("error: '--num-workers' must be greater than zero"),
                "got stdout: \(stdout), stderr: \(stderr)",
            )
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func enableDisableTestabilityDefaultShouldRunWithTestability(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(
            "fails to build the package",
            isIntermittent: true,
        ) {
            // default should run with testability
            try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
                let result = try await execute(
                    ["--vv"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(result.stderr.contains("-enable-testing"))
            }
        } when: {
            buildSystem == .swiftbuild && .windows == ProcessInfo.hostOperatingSystem
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .SWBINTTODO("Test currently fails due to 'error: build failed'"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func enableDisableTestabilityDisabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        // disabled
        try await withKnownIssue("fails to build", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
                let error = await #expect(throws: SwiftPMError.self) {
                    try await execute(
                        ["--disable-testable-imports", "--vv"],
                        packagePath: fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
                guard case let SwiftPMError.executionFailure(_, stdout, stderr) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }

                #expect(
                    stderr.contains("was not compiled for testing") || stderr.contains("ignore swiftmodule built without '-enable-testing'"),
                    "got stdout: \(stdout), stderr: \(stderr)",
                )
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func enableDisableTestabilityEnabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("failes to build the package", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
                let result = try await execute(
                    ["--enable-testable-imports", "--vv"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(result.stderr.contains("-enable-testing"))
            }
        } when: {
            (buildSystem == .swiftbuild && .windows == ProcessInfo.hostOperatingSystem)
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .tags(
            .Feature.TargetType.Executable,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testableExecutableWithDifferentlyNamedExecutableProduct(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestableExeWithDifferentProductName") { fixturePath in
                let result = try await execute(
                    ["--vv"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        } when: {
            .windows == ProcessInfo.hostOperatingSystem
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestParallel_SerialTesting(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
                // First try normal serial testing.
                let error = await #expect(throws: SwiftPMError.self) {
                    try await executeSwiftTest(
                        fixturePath,
                        configuration: configuration,
                        extraArgs: [],
                        throwIfCommandFails: true,
                        buildSystem: buildSystem,
                    )
                }
                guard case SwiftPMError.executionFailure(_, let stdout, _) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }
                #expect(stdout.contains("Executed 2 tests"))
                #expect(!stdout.contains("[3/3]"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.Command.Run,
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestNoParallel,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestParallel_NoParallelArgument(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
                // Try --no-parallel.
                let error = await #expect(throws: SwiftPMError.self) {
                    try await execute(
                        ["--no-parallel"],
                        packagePath: fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
                guard case SwiftPMError.executionFailure(_, let stdout, _) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }
                #expect(stdout.contains("Executed 2 tests"))
                #expect(!stdout.contains("[3/3]"))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }
    }

    @Test(
         .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestParallel,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestParallel_ParallelArgument(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
                // Run tests in parallel.
                let error = await #expect(throws: SwiftPMError.self) {
                    try await execute(
                        ["--parallel"],
                        packagePath: fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem)
                }
                guard case SwiftPMError.executionFailure(_, let stdout, _) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }
                #expect(stdout.contains("testExample1"))
                #expect(stdout.contains("testExample2"))
                #expect(!stdout.contains("'ParallelTestsTests' passed"))
                #expect(stdout.contains("'ParallelTestsFailureTests' failed"))
                #expect(stdout.contains("[3/3]"))
            }
        } when: {
            [ .windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestParallel,
            .Feature.CommandLineArguments.TestOutputXunit,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestParallel_ParallelArgumentWithXunitOutputGeneration(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
                let xUnitOutput = fixturePath.appending("result.xml")
                // Run tests in parallel with verbose output.
                let error = await #expect(throws: SwiftPMError.self) {
                    try await execute(
                        [
                            "--parallel",
                            "--verbose",
                            "--xunit-output",
                            xUnitOutput.pathString,
                        ],
                        packagePath: fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
                guard case SwiftPMError.executionFailure(_, let stdout, _) = try #require(error) else {
                    Issue.record("Incorrect error was raised.")
                    return
                }
                #expect(stdout.contains("testExample1"))
                #expect(stdout.contains("testExample2"))
                #expect(stdout.contains("'ParallelTestsTests' passed"))
                #expect(stdout.contains("'ParallelTestsFailureTests' failed"))
                #expect(stdout.contains("[3/3]"))

                // Check the xUnit output.
                expectFileExists(at: xUnitOutput, "\(xUnitOutput) does not exist")
                let contents: String = try localFileSystem.readFileContents(xUnitOutput)
                #expect(contents.contains("tests=\"3\" failures=\"1\""))
                let timeRegex = try Regex("time=\"[0-9]+\\.[0-9]+\"")
                #expect(contents.contains(timeRegex))
                #expect(!contents.contains("time=\"0.0\""))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestParallel,
            .Feature.CommandLineArguments.TestOutputXunit,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestXMLOutputWhenEmpty(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/EmptyTestsPkg") { fixturePath in
                let xUnitOutput = fixturePath.appending("result.xml")
                // Run tests in parallel with verbose output.
                _ = try await execute(
                    ["--parallel", "--verbose", "--xunit-output", xUnitOutput.pathString],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                ).stdout

                // Check the xUnit output.
                expectFileExists(at: xUnitOutput)
                let contents: String = try localFileSystem.readFileContents(xUnitOutput)
                #expect(contents.contains("tests=\"0\" failures=\"0\""))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }
    }

    enum TestRunner {
        case XCTest
        case SwiftTesting

        var fileSuffix: String {
            switch self {
            case .XCTest: return ""
            case .SwiftTesting: return "-swift-testing"
            }
        }
    }

    public typealias SwiftTestXMLOutputData = (
        fixtureName: String,
        testRunner: TestRunner,
        enableExperimentalFlag: Bool,
        matchesPattern: [String],
        configuration: BuildConfiguration,
        id: String
    )

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestParallel,
            .Feature.CommandLineArguments.TestOutputXunit,
            .Feature.CommandLineArguments.TestEnableXCTest,
            .Feature.CommandLineArguments.TestEnableSwiftTesting,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms.filter { $0 != .xcode }, [
            (
                fixtureName: "Miscellaneous/TestSingleFailureXCTest",
                testRunner: TestRunner.XCTest,
                enableExperimentalFlag: true,
                matchesPattern: ["Purposely failing &amp; validating XML espace &quot;'&lt;&gt;"],
                configuration: BuildConfiguration.debug,
                id: "Single XCTest Test Failure Message With Flag Enabled",
            ),
            (
                fixtureName: "Miscellaneous/TestSingleFailureSwiftTesting",
                testRunner: TestRunner.SwiftTesting,
                enableExperimentalFlag: true,
                matchesPattern: ["Purposely failing &amp; validating XML espace &quot;'&lt;&gt;"],
                configuration: BuildConfiguration.debug,
                id: "Single Swift Testing Test Failure Message With Flag Enabled",
            ),
            (
                fixtureName: "Miscellaneous/TestSingleFailureXCTest",
                testRunner: TestRunner.XCTest,
                enableExperimentalFlag: false,
                matchesPattern: ["failure"],
                configuration: BuildConfiguration.debug,
                id: "Single XCTest Test Failure Message With Flag Disabled",
            ),
            (
                fixtureName: "Miscellaneous/TestSingleFailureSwiftTesting",
                testRunner: TestRunner.SwiftTesting,
                enableExperimentalFlag: false,
                matchesPattern: ["Purposely failing &amp; validating XML espace &quot;'&lt;&gt;"],
                configuration: BuildConfiguration.debug,
                id: "Single Swift Testing Test Failure Message With Flag Disabled",
            ),
            (
                fixtureName: "Miscellaneous/TestMultipleFailureXCTest",
                testRunner: TestRunner.XCTest,
                enableExperimentalFlag: true,
                matchesPattern: [
                    "Test failure 1",
                    "Test failure 2",
                    "Test failure 3",
                    "Test failure 4",
                    "Test failure 5",
                    "Test failure 6",
                    "Test failure 7",
                    "Test failure 8",
                    "Test failure 9",
                    "Test failure 10",
                ],
                configuration: BuildConfiguration.debug,
                id: "Single Multiple Test Failure Message With Flag Enabled",
            ),
            (
                fixtureName: "Miscellaneous/TestMultipleFailureSwiftTesting",
                testRunner: TestRunner.SwiftTesting,
                enableExperimentalFlag: true,
                matchesPattern: [
                    "ST Test failure 1",
                    "ST Test failure 2",
                    "ST Test failure 3",
                    "ST Test failure 4",
                    "ST Test failure 5",
                    "ST Test failure 6",
                    "ST Test failure 7",
                    "ST Test failure 8",
                    "ST Test failure 9",
                    "ST Test failure 10",
                ],
                configuration: BuildConfiguration.debug,
                id: "Multiple Swift Testing Test Failure Message With Flag Enabled",
            ),
            (
                fixtureName: "Miscellaneous/TestMultipleFailureXCTest",
                testRunner: TestRunner.XCTest,
                enableExperimentalFlag: false,
                matchesPattern: [
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                    "failure",
                ],
                configuration: BuildConfiguration.debug,
                id: "Multiple XCTest Tests Failure Message With Flag Disabled",
            ),
            (
                fixtureName: "Miscellaneous/TestMultipleFailureSwiftTesting",
                testRunner: TestRunner.SwiftTesting,
                enableExperimentalFlag: false,
                matchesPattern: [
                    "ST Test failure 1",
                    "ST Test failure 2",
                    "ST Test failure 3",
                    "ST Test failure 4",
                    "ST Test failure 5",
                    "ST Test failure 6",
                    "ST Test failure 7",
                    "ST Test failure 8",
                    "ST Test failure 9",
                    "ST Test failure 10",
                ],
                configuration: BuildConfiguration.debug,
                id: "Multiple Swift Testing Tests Failure Message With Flag Disabled",
            )
        ]
    )
    func swiftTestXMLOutputFailureMessage(
        buildSystem: BuildSystemProvider.Kind,
        tcdata: SwiftTestXMLOutputData,
    ) async throws {
        // windows issue not recorded for:
        //   - native, single, XCTest, experimental true
        //   - native, single, XCTest, experimental false
        try await withKnownIssue( isIntermittent: true) {
            try await fixture(name: tcdata.fixtureName) { fixturePath in
                // GIVEN we have a Package with a failing \(testRunner) test cases
                let xUnitOutput = fixturePath.appending("result.xml")
                let xUnitUnderTest = fixturePath.appending("result\(tcdata.testRunner.fileSuffix).xml")

                // WHEN we execute swift-test in parallel while specifying xUnit generation
                let extraCommandArgs = tcdata.enableExperimentalFlag ? ["--experimental-xunit-message-failure"] : []
                let (stdout, stderr) = try await execute(
                    [
                        "--parallel",
                        "--verbose",
                        "--enable-swift-testing",
                        "--enable-xctest",
                        "--xunit-output",
                        xUnitOutput.pathString,
                    ] + extraCommandArgs,
                    packagePath: fixturePath,
                    configuration: tcdata.configuration,
                    buildSystem: buildSystem,
                    throwIfCommandFails: false,
                )

                if !FileManager.default.fileExists(atPath: xUnitUnderTest.pathString) {
                    // If the build failed then produce an output dump of what happened during the execution
                    print("\(stdout)")
                    print("\(stderr)")
                }

                // THEN we expect \(xUnitUnderTest) to exists
                expectFileExists(at: xUnitUnderTest)
                let contents: String = try localFileSystem.readFileContents(xUnitUnderTest)
                // AND that the xUnit file has the expected contents
                for match in tcdata.matchesPattern {
                    #expect(contents.contains(match))
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    /// An argument to the test function `noteXCTestFailures()`.
    struct XCTestFailureNoteTestArgument: CustomStringConvertible {
        /// The relative path to a test fixture in this project.
        var fixturePath: String

        /// The setting representing whether XCTest should be enabled or disabled
        /// for the test command, if any. When the value of this property is `nil`,
        /// no flag will be passed. If non-`nil`, either `--enable-xctest` or
        /// `--disable-xctest` will be passed representing the value. The default
        /// value is `nil`, meaning no flag will be passed but the command defaults
        /// to having XCTest enabled.
        var isXCTestEnabled: Bool? = nil

        /// The setting representing whether Swift Testing should be enabled or disabled
        /// for the test command, if any. When the value of this property is `nil`,
        /// no flag will be passed. If non-`nil`, either `--enable-swift-testing` or
        /// `--disable-swift-testing` will be passed representing the value. The default
        /// value is `nil`, meaning no flag will be passed but the command defaults
        /// to having Swift Testing enabled.
        var isSwiftTestingEnabled: Bool? = nil

        /// Whether the test command output is expected to include the note.
        var expectNote: Bool

        var description: String {
            var description = "fixture: '\((fixturePath as NSString).lastPathComponent)'"
            if let isXCTestEnabled {
                description.append(", XCTest enabled: \(isXCTestEnabled)")
            }
            if let isSwiftTestingEnabled {
                description.append(", Swift Testing enabled: \(isSwiftTestingEnabled)")
            }
            description.append(", expectNote: \(expectNote)")
            return description
        }
    }

    /// Test whether a note is emitted to stdout indicating that XCTests failed
    /// after Swift Testing tests finish running.
    @Test(
        .tags(
            .Feature.TargetType.Test,
            .Feature.CommandLineArguments.TestEnableXCTest,
            .Feature.CommandLineArguments.TestDisableXCTest,
            .Feature.CommandLineArguments.TestEnableSwiftTesting,
            .Feature.CommandLineArguments.TestDisableSwiftTesting,
        ),
        arguments: [
            .init(
                fixturePath: "Miscellaneous/TestDiscovery/Simple",
                expectNote: false,
            ),
            .init(
                fixturePath: "Miscellaneous/TestSingleFailureXCTest",
                expectNote: true,
            ),
            .init(
                fixturePath: "Miscellaneous/TestSingleFailureSwiftTesting",
                expectNote: false,
            ),
            .init(
                fixturePath: "Miscellaneous/TestSingleFailureXCTest",
                isXCTestEnabled: false,
                expectNote: false,
            ),
            .init(
                fixturePath: "Miscellaneous/TestSingleFailureXCTest",
                isSwiftTestingEnabled: false,
                expectNote: false,
            ),
            .init(
                fixturePath: "Miscellaneous/TestSingleFailureXCTest",
                isXCTestEnabled: false,
                isSwiftTestingEnabled: false,
                expectNote: false,
            ),
        ] as [XCTestFailureNoteTestArgument]
    )
    func noteXCTestFailures(noteArgument arg: XCTestFailureNoteTestArgument) async throws {
        try await fixture(name: arg.fixturePath) { fixturePath in
            var args: [String] = []

            switch arg.isXCTestEnabled {
            case .none: break
            case .some(true): args.append("--enable-xctest")
            case .some(false): args.append("--disable-xctest")
            }

            switch arg.isSwiftTestingEnabled {
            case .none: break
            case .some(true): args.append("--enable-swift-testing")
            case .some(false): args.append("--disable-swift-testing")
            }

            let (stdout, stderr) = try await execute(
                args,
                packagePath: fixturePath,
                buildSystem: .native,
                throwIfCommandFails: false,
            )
            #expect(stdout.contains(SwiftTestCommand.xctestFailedNote) == arg.expectNote, "stdout: \(stdout), stderr: \(stderr)")
        }
    }

    @Test(
         .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestFilter,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestFilter(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
                let (stdout, _) = try await execute(
                    ["--filter", ".*1"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("testExample1"))
                #expect(!stdout.contains("testExample2"))
                #expect(!stdout.contains("testExample3"))
                #expect(!stdout.contains("testExample4"))
            }

            try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
                let (stdout, _) = try await execute(
                    ["--filter", "SomeTests", "--skip", ".*1", "--filter", "testExample3"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // in "swift test" test output goes to stdout
                #expect(!stdout.contains("testExample1"))
                #expect(stdout.contains("testExample2"))
                #expect(stdout.contains("testExample3"))
                #expect(!stdout.contains("testExample4"))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestSkip,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func swiftTestSkip(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
                let (stdout, _) = try await execute(
                    ["--skip", "SomeTests"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // in "swift test" test output goes to stdout
                #expect(!stdout.contains("testExample1"))
                #expect(!stdout.contains("testExample2"))
                #expect(stdout.contains("testExample3"))
                #expect(stdout.contains("testExample4"))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }

        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
                let (stdout, _) = try await execute(
                    [
                        "--filter",
                        "ExampleTests",
                        "--skip",
                        ".*2",
                        "--filter",
                        "MoreTests",
                        "--skip", "testExample3",
                    ],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // in "swift test" test output goes to stdout
                #expect(stdout.contains("testExample1"))
                #expect(!stdout.contains("testExample2"))
                #expect(!stdout.contains("testExample3"))
                #expect(stdout.contains("testExample4"))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }

        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
                let (stdout, _) = try await execute(
                    ["--skip", "Tests"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // in "swift test" test output goes to stdout
                #expect(!stdout.contains("testExample1"))
                #expect(!stdout.contains("testExample2"))
                #expect(!stdout.contains("testExample3"))
                #expect(!stdout.contains("testExample4"))
            }
        } when: {
            [.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .SWBINTTODO("Fails to find test executable"),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/8722", relationship: .fixedBy),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func enableTestDiscoveryDeprecation(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("Fails to find test executable") {
            let compilerDiagnosticFlags = ["-Xswiftc", "-Xfrontend", "-Xswiftc", "-Rmodule-interface-rebuild"]
            // should emit when LinuxMain is present
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await execute(
                    ["--enable-test-discovery"] + compilerDiagnosticFlags,
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(stderr.contains("warning: '--enable-test-discovery' option is deprecated"))
            }

            #if canImport(Darwin)
                let expected = true
            // should emit when LinuxMain is not present
            #else
                // should not emit when LinuxMain is present
                let expected = false
            #endif
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                try localFileSystem.writeFileContents(fixturePath.appending(components: "Tests", SwiftModule.defaultTestEntryPointName), bytes: "fatalError(\"boom\")")
                let (_, stderr) = try await execute(
                    ["--enable-test-discovery"] + compilerDiagnosticFlags,
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(stderr.contains("warning: '--enable-test-discovery' option is deprecated") == expected)
            }
        } when: {
            buildSystem == .swiftbuild && [.linux, .windows].contains(ProcessInfo.hostOperatingSystem)
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .SWBINTTODO("Fails to find test executable"),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/8722", relationship: .fixedBy),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func listWithoutBuildingFirst(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("Fails to find test executable") {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (stdout, stderr) = try await execute(
                    ["list"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // build was run
                #expect(stderr.contains("Build complete!"))

                // getting the lists
                #expect(stdout.contains("SimpleTests.SimpleTests/testExample1"))
                #expect(stdout.contains("SimpleTests.SimpleTests/test_Example2"))
                #expect(stdout.contains("SimpleTests.SimpleTests/testThrowing"))
            }
        } when: {
            (buildSystem == .swiftbuild && .windows == ProcessInfo.hostOperatingSystem)
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.BuildTests,
        ),
        .SWBINTTODO("Fails to find test executable when run in self-hosted pipeline"),
        .SWBINTTODO("Linux: fails to build with --build-test in Smoke Tests"),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/8722", relationship: .fixedBy),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func listBuildFirstThenList(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            // build first
            try await withKnownIssue("Fails to save attachment", isIntermittent: true) {
                // This might be intermittently failing on windows
                let (buildStdout, _) = try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    extraArgs: ["--build-tests"],
                    buildSystem: buildSystem,
                )
                #expect(buildStdout.contains("Build complete!"))
            } when: {
                (buildSystem == .native && configuration == .release) // error: module 'Simple' was not compiled for testing
                || (configuration == .release && buildSystem != .native && ProcessInfo.hostOperatingSystem != .windows) // (configuration == .release)
                || (buildSystem != .native && ProcessInfo.hostOperatingSystem == .windows) // || (ProcessInfo.hostOperatingSystem == .windows)
            }

            // list
            try await withKnownIssue("Fails to find test executable", isIntermittent: true) { // windows; issue not recorded
                let (listStdout, listStderr) = try await execute(
                    ["list"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                // build was run
                #expect(listStderr.contains("Build complete!"))
                // getting the lists
                #expect(listStdout.contains("SimpleTests.SimpleTests/testExample1"))
                #expect(listStdout.contains("SimpleTests.SimpleTests/test_Example2"))
                #expect(listStdout.contains("SimpleTests.SimpleTests/testThrowing"))
            } when: {
                (configuration == .release && ProcessInfo.hostOperatingSystem != .macOS)
                || (buildSystem == .swiftbuild && [.linux].contains(ProcessInfo.hostOperatingSystem))
                || (buildSystem == .swiftbuild && [.windows].contains(ProcessInfo.hostOperatingSystem)) && configuration == .debug
            }
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.BuildTests,
        ),
        .SWBINTTODO("Fails to find test executable"),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/8722", relationship: .fixedBy),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func listBuildFirstThenListWhileSkippingBuild(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("Failed to find test executable, or getting error: module 'Simple' was not compiled for testing, onMacOS", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                // build first
                try await withKnownIssue("Failed to save attachment", isIntermittent: true) {
                    // This might be intermittently failing on windows
                    let (buildStdout, _) = try await executeSwiftBuild(
                        fixturePath,
                        configuration: configuration,
                        extraArgs: ["--build-tests"],
                        buildSystem: buildSystem,
                    )
                    #expect(buildStdout.contains("Build complete!"))
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }

                // list while skipping build
                let (listStdout, listStderr) = try await execute(["list", "--skip-build"], packagePath: fixturePath, buildSystem: buildSystem)
                // build was not run
                #expect(!listStderr.contains("Build complete!"))
                // getting the lists
                #expect(listStdout.contains("SimpleTests.SimpleTests/testExample1"))
                #expect(listStdout.contains("SimpleTests.SimpleTests/test_Example2"))
                #expect(listStdout.contains("SimpleTests.SimpleTests/testThrowing"))
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func listWithSkipBuildAndNoBuildArtifacts(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let error = await #expect(throws: SwiftPMError.self) {
                try await execute(
                    ["list", "--skip-build"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                    throwIfCommandFails: true,
                )
            }
            guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                Issue.record("Incorrect error was raised.")
                return
            }
            #expect(
                stderr.contains("Test build artifacts were not found in the build folder"),
                "got stdout: \(stdout), stderr: \(stderr)",
            )
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestEnableSwiftTesting,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func basicSwiftTestingIntegration(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("Fails to find the test executable") {
            try await fixture(name: "Miscellaneous/TestDiscovery/SwiftTesting") { fixturePath in
                let (stdout, stderr) = try await execute(
                    ["--enable-swift-testing", "--disable-xctest"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(
                    stdout.contains(#"Test "SOME TEST FUNCTION" started"#),
                    "Expectation not met.  got '\(stdout)'\nstderr: '\(stderr)'"
                )
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .skipHostOS(.macOS),  // because this was guarded with `#if !canImport(Darwin)`
        .SWBINTTODO("This is a PIF builder missing GUID problem. Further investigation is needed."),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func generatedMainIsConcurrencySafe_XCTest(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            let strictConcurrencyFlags = ["-Xswiftc", "-strict-concurrency=complete"]
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await execute(
                    strictConcurrencyFlags,
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(!stderr.contains("is not concurrency-safe"))
            }
        } when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem != .linux)
        }
    }
    @Test(
         .tags(
            .Feature.TargetType.Executable,
        ),
        .skipHostOS(.macOS),  // because this was guarded with `#if !canImport(Darwin)`
        .SWBINTTODO("This is a PIF builder missing GUID problem. Further investigation is needed."),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func generatedMainIsExistentialAnyClean(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue(isIntermittent: true) {
            let existentialAnyFlags = ["-Xswiftc", "-enable-upcoming-feature", "-Xswiftc", "ExistentialAny"]
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await execute(
                    existentialAnyFlags,
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(!stderr.contains("error: use of protocol"))
            }
        } when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows)
        }
    }

    @Test(
         .tags(
            .Feature.TargetType.Executable,
        ),
        .IssueWindowsPathTestsFailures,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8602", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func libraryEnvironmentVariable(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("produces a filepath that is too long, needs investigation", isIntermittent: true) {
            try await fixture(name: "Miscellaneous/CheckTestLibraryEnvironmentVariable") { fixturePath in
                var extraEnv = Environment()
                if try UserToolchain.default.swiftTestingPath != nil {
                    extraEnv["CONTAINS_SWIFT_TESTING"] = "1"
                }
                await #expect(throws: Never.self) {
                    try await executeSwiftTest(
                        fixturePath,
                        configuration: configuration,
                        env: extraEnv,
                        buildSystem: buildSystem,
                    )
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestDisableSwiftTesting,
        ),
        .SWBINTTODO("Fails to find test executable"),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/8722", relationship: .fixedBy),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func XCTestOnlyDoesNotLogAboutNoMatchingTests(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("Fails to find test executable",  isIntermittent: true) {
            try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
                let (_, stderr) = try await execute(
                    ["--disable-swift-testing"],
                    packagePath: fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                #expect(!stderr.contains("No matching test cases were run"))
            }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
        .tags(
            .Feature.TargetType.Executable,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/6605", relationship: .verifies),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8602", relationship: .defect),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func fatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let configuration = BuildConfiguration.debug
        try await withKnownIssue("Windows path issue", isIntermittent: true) {
            // GIVEN we have a Swift Package that has a fatalError building the tests
            let expected = 1
            try await fixture(name: "Miscellaneous/Errors/FatalErrorInSingleXCTest/TypeLibrary") { fixturePath in
                // WHEN swift-test is executed
                let error = await #expect(throws: SwiftPMError.self) {
                    try await self.execute(
                        [],
                        packagePath: fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }

                // THEN I expect a failure
                guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = try #require(error) else {
                    Issue.record("Building the package was expected to fail, but it was successful.")
                    return
                }

                let matchString = "error: fatalError"
                let stdoutMatches = getNumberOfMatches(of: matchString, in: stdout)
                let stderrMatches = getNumberOfMatches(of: matchString, in: stderr)
                let actualNumMatches = stdoutMatches + stderrMatches

                // AND a fatal error message is printed \(expected) times
                let expectationMessage = [
                    "Actual (\(actualNumMatches)) is not as expected (\(expected))",
                    "stdout: \(stdout.debugDescription)",
                    "stderr: \(stderr.debugDescription)",
                ].joined(separator: "\n")
                #expect(
                    actualNumMatches == expected,
                    "\(expectationMessage)",
                )
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }
    }

    @Test(
            .IssueWindowsLongPath,
            .tags(
                .Feature.TargetType.Executable,
            ),
            arguments: SupportedBuildSystemOnAllPlatforms,
        )
        func testableExecutableWithEmbeddedResources(
            buildSystem: BuildSystemProvider.Kind,
        ) async throws {
            let configuration = BuildConfiguration.debug
            try await withKnownIssue(isIntermittent: true) {
                try await fixture(name: "Miscellaneous/TestableExeWithResources") { fixturePath in
                    let result = try await execute(
                        ["--vv"],
                        packagePath: fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
            } when: {
                .windows == ProcessInfo.hostOperatingSystem
                || ProcessInfo.processInfo.environment["SWIFTCI_EXHIBITS_GH_9524"] != nil
            }
         }

}
