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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func usage(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
        let stdout = try await execute(
            ["-help"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        #expect(stdout.contains("USAGE: swift test"), "got stdout:\n\(stdout)")
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func experimentalXunitMessageFailureArgumentIsHidden(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func seeAlso(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
        let stdout = try await execute(
            ["--help"],
            configuration: configuration,
            buildSystem: buildSystem,
        ).stdout
        #expect(stdout.contains("SEE ALSO: swift build, swift run, swift package"), "got stdout:\n\(stdout)")
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func version(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func toolsetRunner(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
                switch buildSystem {
                    case .native:
                        #expect(stderr.contains("Compiling"))
                        #expect(stderr.contains("Linking"))
                    case .swiftbuild:
                        break
                    case .xcode:
                        Issue.record("Test expectation have not been implemented")
                }
            }
        } when: {
            (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows)
            // || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSmokeTestPipeline)
            // || (buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .linux && CiEnvironment.runningInSelfHostedPipeline) // error: SwiftCompile normal x86_64 /tmp/Miscellaneous_EchoExecutable.sxkNTX/Miscellaneous_EchoExecutable/.build/x86_64-unknown-linux-gnu/Intermediates.noindex/EchoExecutable.build/Debug-linux/TestSuite-test-runner.build/DerivedSources/test_entry_point.swift failed with a nonzero exit code
        }
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func numWorkersParallelRequirement(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func numWorkersValueSetToZeroRaisesAnError(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func enableDisableTestabilityDefaultShouldRunWithTestability(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func enableDisableTestabilityDisabled(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func enableDisableTestabilityEnabled(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func testableExecutableWithDifferentlyNamedExecutableProduct(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestParallel_SerialTesting(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestParallel_NoParallelArgument(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
         .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestParallel,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestParallel_ParallelArgument(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestParallel_ParallelArgumentWithXunitOutputGeneration(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestXMLOutputWhenEmpty(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms), [
                (
                    fixtureName: "Miscellaneous/TestSingleFailureXCTest",
                    testRunner: TestRunner.XCTest,
                    enableExperimentalFlag: true,
                    matchesPattern: ["Purposely failing &amp; validating XML espace &quot;'&lt;&gt;"],
                    id: "Single XCTest Test Failure Message With Flag Enabled",
                ),
                (
                    fixtureName: "Miscellaneous/TestSingleFailureSwiftTesting",
                    testRunner: TestRunner.SwiftTesting,
                    enableExperimentalFlag: true,
                    matchesPattern: ["Purposely failing &amp; validating XML espace &quot;'&lt;&gt;"],
                    id: "Single Swift Testing Test Failure Message With Flag Enabled",
                ),
                (
                    fixtureName: "Miscellaneous/TestSingleFailureXCTest",
                    testRunner: TestRunner.XCTest,
                    enableExperimentalFlag: false,
                    matchesPattern: ["failure"],
                    id: "Single XCTest Test Failure Message With Flag Disabled",
                ),
                (
                    fixtureName: "Miscellaneous/TestSingleFailureSwiftTesting",
                    testRunner: TestRunner.SwiftTesting,
                    enableExperimentalFlag: false,
                    matchesPattern: ["Purposely failing &amp; validating XML espace &quot;'&lt;&gt;"],
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
                    id: "Multiple Swift Testing Tests Failure Message With Flag Disabled",
                )
            ],
    )
    func swiftTestXMLOutputFailureMessage(
        buildData: BuildData,
        tcdata: SwiftTestXMLOutputData,
    ) async throws {
        // windows issue not recorded for:
        //   - native, single, XCTest, experimental true
        //   - native, single, XCTest, experimental false
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
                    configuration: configuration,
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

    @Test(
         .tags(
            .Feature.TargetType.Executable,
            .Feature.CommandLineArguments.TestFilter,
        ),
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8479", relationship: .defect),
        .SWBINTTODO("Result XML could not be found. The build fails because of missing test helper generation logic for non-macOS platforms"),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestFilter(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func swiftTestSkip(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func enableTestDiscoveryDeprecation(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
            // buildSystem == .swiftbuild && [.linux, .windows].contains(ProcessInfo.hostOperatingSystem)
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func listWithoutBuildingFirst(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func listBuildFirstThenList(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func listBuildFirstThenListWhileSkippingBuild(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func listWithSkipBuildAndNoBuildArtifacts(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func basicSwiftTestingIntegration(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func generatedMainIsConcurrencySafe_XCTest(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func generatedMainIsExistentialAnyClean(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func libraryEnvironmentVariable(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func XCTestOnlyDoesNotLogAboutNoMatchingTests(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func fatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation(
        buildData: BuildData,
    ) async throws {
        let buildSystem = buildData.buildSystem
        let configuration = buildData.config
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
            arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
        )
        func testableExecutableWithEmbeddedResources(
            buildData: BuildData,
        ) async throws {
            let buildSystem = buildData.buildSystem
            let configuration = buildData.config
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
