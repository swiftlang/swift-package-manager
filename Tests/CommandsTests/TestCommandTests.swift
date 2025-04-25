//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Commands
import SPMBuildCore
import PackageModel
import _InternalTestSupport
import TSCTestSupport
import XCTest

class TestCommandTestCase: CommandsBuildProviderTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(type(of: self) == TestCommandTestCase.self, "Skipping this test since it will be run in subclasses that will provide different build systems to test.")
    }

    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        throwIfCommandFails: Bool = true
    ) async throws -> (stdout: String, stderr: String) {
        try await executeSwiftTest(
            packagePath,
            extraArgs: args,
            throwIfCommandFails: throwIfCommandFails,
            buildSystem: buildSystemProvider
        )
    }

    func testUsage() async throws {
        let stdout = try await execute(["-help"]).stdout
        XCTAssert(stdout.contains("USAGE: swift test"), "got stdout:\n" + stdout)
    }

    func testExperimentalXunitMessageFailureArgumentIsHidden() async throws {
        let stdout = try await execute(["--help"]).stdout
        XCTAssertFalse(
            stdout.contains("--experimental-xunit-message-failure"),
            "got stdout:\n" + stdout
        )
        XCTAssertFalse(
            stdout.contains("When Set, enabled an experimental message failure content (XCTest only)."),
            "got stdout:\n" + stdout
        )
    }

    func testSeeAlso() async throws {
        let stdout = try await execute(["--help"]).stdout
        XCTAssert(stdout.contains("SEE ALSO: swift build, swift run, swift package"), "got stdout:\n" + stdout)
    }

    func testVersion() async throws {
        let stdout = try await execute(["--version"]).stdout
        XCTAssertMatch(stdout, .regex(#"Swift Package Manager -( \w+ )?\d+.\d+.\d+(-\w+)?"#))
    }

    // `echo.sh` script from the toolset won't work on Windows
    #if !os(Windows)
        func testToolsetRunner() async throws {
            try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
                let (stdout, stderr) = try await execute(
                    ["--toolset", "\(fixturePath)/toolset.json"], packagePath: fixturePath)

                // We only expect tool's output on the stdout stream.
                XCTAssertMatch(stdout, .contains("sentinel"))
                XCTAssertMatch(stdout, .contains("\(fixturePath)"))

                // swift-build-tool output should go to stderr.
                XCTAssertMatch(stderr, .regex("Compiling"))
                XCTAssertMatch(stderr, .contains("Linking"))
            }
        }
    #endif

    func testNumWorkersParallelRequirement() async throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            await XCTAssertThrowsCommandExecutionError(try await execute(["--num-workers", "1"])) { error in
                XCTAssertMatch(error.stderr, .contains("error: --num-workers must be used with --parallel"))
            }
        }
    }

    func testNumWorkersValue() async throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try await fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            await XCTAssertThrowsCommandExecutionError(try await execute(["--parallel", "--num-workers", "0"])) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--num-workers' must be greater than zero"))
            }
        }
    }

    func testEnableDisableTestability() async throws {
        // default should run with testability
        try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try await execute(["--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }

        // disabled
        try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            await XCTAssertThrowsCommandExecutionError(try await execute(["--disable-testable-imports", "--vv"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("was not compiled for testing"))
            }
        }

        // enabled
        try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try await execute(["--enable-testable-imports", "--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }
    }

    func testWithReleaseConfiguration() async throws {
        try await fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try await execute(["-c", "release", "--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }
    }

    func testSwiftTestParallel() async throws {
        try await fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            // First try normal serial testing.
            await XCTAssertThrowsCommandExecutionError(try await execute([], packagePath: fixturePath)) { error in
                // in "swift test" test output goes to stdout
                XCTAssertMatch(error.stdout, .contains("Executed 2 tests"))
                XCTAssertNoMatch(error.stdout, .contains("[3/3]"))
            }

            // Try --no-parallel.
            await XCTAssertThrowsCommandExecutionError(try await execute(["--no-parallel"], packagePath: fixturePath)) { error in
                // in "swift test" test output goes to stdout
                XCTAssertMatch(error.stdout, .contains("Executed 2 tests"))
                XCTAssertNoMatch(error.stdout, .contains("[3/3]"))
            }

            // Run tests in parallel.
            await XCTAssertThrowsCommandExecutionError(try await execute(["--parallel"], packagePath: fixturePath)) { error in
                // in "swift test" test output goes to stdout
                XCTAssertMatch(error.stdout, .contains("testExample1"))
                XCTAssertMatch(error.stdout, .contains("testExample2"))
                XCTAssertNoMatch(error.stdout, .contains("'ParallelTestsTests' passed"))
                XCTAssertMatch(error.stdout, .contains("'ParallelTestsFailureTests' failed"))
                XCTAssertMatch(error.stdout, .contains("[3/3]"))
            }

            do {
                let xUnitOutput = fixturePath.appending("result.xml")
                // Run tests in parallel with verbose output.
                await XCTAssertThrowsCommandExecutionError(
                    try await execute(["--parallel", "--verbose", "--xunit-output", xUnitOutput.pathString], packagePath: fixturePath)
                ) { error in
                    // in "swift test" test output goes to stdout
                    XCTAssertMatch(error.stdout, .contains("testExample1"))
                    XCTAssertMatch(error.stdout, .contains("testExample2"))
                    XCTAssertMatch(error.stdout, .contains("'ParallelTestsTests' passed"))
                    XCTAssertMatch(error.stdout, .contains("'ParallelTestsFailureTests' failed"))
                    XCTAssertMatch(error.stdout, .contains("[3/3]"))
                }

                // Check the xUnit output.
                XCTAssertFileExists(xUnitOutput)
                let contents: String = try localFileSystem.readFileContents(xUnitOutput)
                XCTAssertMatch(contents, .contains("tests=\"3\" failures=\"1\""))
                XCTAssertMatch(contents, .regex("time=\"[0-9]+\\.[0-9]+\""))
                XCTAssertNoMatch(contents, .contains("time=\"0.0\""))
            }
        }
    }

    func testSwiftTestXMLOutputWhenEmpty() async throws {
        try await fixture(name: "Miscellaneous/EmptyTestsPkg") { fixturePath in
            let xUnitOutput = fixturePath.appending("result.xml")
            // Run tests in parallel with verbose output.
            _ = try await execute(["--parallel", "--verbose", "--xunit-output", xUnitOutput.pathString], packagePath: fixturePath).stdout

            // Check the xUnit output.
            XCTAssertFileExists(xUnitOutput)
            let contents: String = try localFileSystem.readFileContents(xUnitOutput)
            XCTAssertMatch(contents, .contains("tests=\"0\" failures=\"0\""))
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
    func _testSwiftTestXMLOutputFailureMessage(
        fixtureName: String,
        testRunner: TestRunner,
        enableExperimentalFlag: Bool,
        matchesPattern: [StringPattern]
    ) async throws {
        try await fixture(name: fixtureName) { fixturePath in
            // GIVEN we have a Package with a failing \(testRunner) test cases
            let xUnitOutput = fixturePath.appending("result.xml")
            let xUnitUnderTest = fixturePath.appending("result\(testRunner.fileSuffix).xml")

            // WHEN we execute swift-test in parallel while specifying xUnit generation
            let extraCommandArgs = enableExperimentalFlag ? ["--experimental-xunit-message-failure"]: []
            let (stdout, stderr) = try await execute(
                [
                    "--parallel",
                    "--verbose",
                    "--enable-swift-testing",
                    "--enable-xctest",
                    "--xunit-output",
                    xUnitOutput.pathString
                ] + extraCommandArgs,
                packagePath: fixturePath,
                throwIfCommandFails: false
            )

            if !FileManager.default.fileExists(atPath: xUnitUnderTest.pathString) {
                // If the build failed then produce a output dump of what happened during the execution
                print("\(stdout)")
                print("\(stderr)")
            }

            // THEN we expect \(xUnitUnderTest) to exists
            XCTAssertFileExists(xUnitUnderTest)
            let contents: String = try localFileSystem.readFileContents(xUnitUnderTest)
            // AND that the xUnit file has the expected contents
            for match in matchesPattern {
                XCTAssertMatch(contents, match)
            }
        }
    }

    func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagEnabledXCTest() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestSingleFailureXCTest",
            testRunner: .XCTest,
            enableExperimentalFlag: true,
            matchesPattern: [.contains("Purposely failing &amp; validating XML espace &quot;'&lt;&gt;")]
        )
    }

    func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagEnabledSwiftTesting() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestSingleFailureSwiftTesting",
            testRunner: .SwiftTesting,
            enableExperimentalFlag: true,
            matchesPattern: [.contains("Purposely failing &amp; validating XML espace &quot;'&lt;&gt;")]
        )
    }
    func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagDisabledXCTest() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestSingleFailureXCTest",
            testRunner: .XCTest,
            enableExperimentalFlag: false,
            matchesPattern: [.contains("failure")]
        )
    }

    func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagDisabledSwiftTesting() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestSingleFailureSwiftTesting",
            testRunner: .SwiftTesting,
            enableExperimentalFlag: false,
            matchesPattern: [.contains("Purposely failing &amp; validating XML espace &quot;'&lt;&gt;")]
        )
    }

    func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagEnabledXCTest() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestMultipleFailureXCTest",
            testRunner: .XCTest,
            enableExperimentalFlag: true,
            matchesPattern: [
                .contains("Test failure 1"),
                .contains("Test failure 2"),
                .contains("Test failure 3"),
                .contains("Test failure 4"),
                .contains("Test failure 5"),
                .contains("Test failure 6"),
                .contains("Test failure 7"),
                .contains("Test failure 8"),
                .contains("Test failure 9"),
                .contains("Test failure 10")
            ]
        )
    }

    func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagEnabledSwiftTesting() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestMultipleFailureSwiftTesting",
            testRunner: .SwiftTesting,
            enableExperimentalFlag: true,
            matchesPattern: [
                .contains("ST Test failure 1"),
                .contains("ST Test failure 2"),
                .contains("ST Test failure 3"),
                .contains("ST Test failure 4"),
                .contains("ST Test failure 5"),
                .contains("ST Test failure 6"),
                .contains("ST Test failure 7"),
                .contains("ST Test failure 8"),
                .contains("ST Test failure 9"),
                .contains("ST Test failure 10")
            ]
        )
    }

    func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagDisabledXCTest() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestMultipleFailureXCTest",
            testRunner: .XCTest,
            enableExperimentalFlag: false,
            matchesPattern: [
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure"),
                .contains("failure")
            ]
        )
    }

    func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagDisabledSwiftTesting() async throws {
        try await self._testSwiftTestXMLOutputFailureMessage(
            fixtureName: "Miscellaneous/TestMultipleFailureSwiftTesting",
            testRunner: .SwiftTesting,
            enableExperimentalFlag: false,
            matchesPattern: [
                .contains("ST Test failure 1"),
                .contains("ST Test failure 2"),
                .contains("ST Test failure 3"),
                .contains("ST Test failure 4"),
                .contains("ST Test failure 5"),
                .contains("ST Test failure 6"),
                .contains("ST Test failure 7"),
                .contains("ST Test failure 8"),
                .contains("ST Test failure 9"),
                .contains("ST Test failure 10")
            ]
        )
    }

    func testSwiftTestFilter() async throws {
        try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
            let (stdout, _) = try await execute(["--filter", ".*1"], packagePath: fixturePath)
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testExample3"))
            XCTAssertNoMatch(stdout, .contains("testExample4"))
        }

        try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
            let (stdout, _) = try await execute(["--filter", "SomeTests", "--skip", ".*1", "--filter", "testExample3"], packagePath: fixturePath)
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertMatch(stdout, .contains("testExample2"))
            XCTAssertMatch(stdout, .contains("testExample3"))
            XCTAssertNoMatch(stdout, .contains("testExample4"))
        }
    }

    func testSwiftTestSkip() async throws {
        try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
            let (stdout, _) = try await execute(["--skip", "SomeTests"], packagePath: fixturePath)
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertMatch(stdout, .contains("testExample3"))
            XCTAssertMatch(stdout, .contains("testExample4"))
        }

        try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
            let (stdout, _) = try await execute(["--filter", "ExampleTests", "--skip", ".*2", "--filter", "MoreTests", "--skip", "testExample3"], packagePath: fixturePath)
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testExample3"))
            XCTAssertMatch(stdout, .contains("testExample4"))
        }

        try await fixture(name: "Miscellaneous/SkipTests") { fixturePath in
            let (stdout, _) = try await execute(["--skip", "Tests"], packagePath: fixturePath)
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testExample3"))
            XCTAssertNoMatch(stdout, .contains("testExample4"))
        }
    }

    func testEnableTestDiscoveryDeprecation() async throws {
        let compilerDiagnosticFlags = ["-Xswiftc", "-Xfrontend", "-Xswiftc", "-Rmodule-interface-rebuild"]
        #if canImport(Darwin)
        // should emit when LinuxMain is present
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try await execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }

        // should emit when LinuxMain is not present
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            try localFileSystem.writeFileContents(fixturePath.appending(components: "Tests", SwiftModule.defaultTestEntryPointName), bytes: "fatalError(\"boom\")")
            let (_, stderr) = try await execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }
        #else
        // should emit when LinuxMain is present
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try await execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }
        // should not emit when LinuxMain is present
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            try localFileSystem.writeFileContents(fixturePath.appending(components: "Tests", SwiftModule.defaultTestEntryPointName), bytes: "fatalError(\"boom\")")
            let (_, stderr) = try await execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertNoMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }
        #endif
    }

    func testList() async throws {
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (stdout, stderr) = try await execute(["list"], packagePath: fixturePath)
            // build was run
            XCTAssertMatch(stderr, .contains("Build complete!"))
            // getting the lists
            XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/testExample1"))
            XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/test_Example2"))
            XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/testThrowing"))
        }

        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            // build first
            do {
                let (stdout, _) = try await SwiftPM.Build.execute(["--build-tests"], packagePath: fixturePath)
                XCTAssertMatch(stdout, .contains("Build complete!"))
            }
            // list
            do {
                let (stdout, stderr) = try await execute(["list"], packagePath: fixturePath)
                // build was run
                XCTAssertMatch(stderr, .contains("Build complete!"))
                // getting the lists
                XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/testExample1"))
                XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/test_Example2"))
                XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/testThrowing"))
            }
        }

        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            // build first
            do {
                let (stdout, _) = try await SwiftPM.Build.execute(["--build-tests"], packagePath: fixturePath)
                XCTAssertMatch(stdout, .contains("Build complete!"))
            }
            // list while skipping build
            do {
                let (stdout, stderr) = try await execute(["list", "--skip-build"], packagePath: fixturePath)
                // build was not run
                XCTAssertNoMatch(stderr, .contains("Build complete!"))
                // getting the lists
                XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/testExample1"))
                XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/test_Example2"))
                XCTAssertMatch(stdout, .contains("SimpleTests.SimpleTests/testThrowing"))
            }
        }
    }

    func testListWithSkipBuildAndNoBuildArtifacts() async throws {
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            await XCTAssertThrowsCommandExecutionError(
                try await execute(["list", "--skip-build"], packagePath: fixturePath, throwIfCommandFails: true)
            ) { error in
                XCTAssertMatch(error.stderr, .contains("Test build artifacts were not found in the build folder"))
            }
        }
    }

    func testBasicSwiftTestingIntegration() async throws {
#if !canImport(TestingDisabled)
        try XCTSkipUnless(
            nil != Environment.current["SWIFT_PM_SWIFT_TESTING_TESTS_ENABLED"],
            "Skipping \(#function) because swift-testing tests are not explicitly enabled"
        )
#endif

        try await fixture(name: "Miscellaneous/TestDiscovery/SwiftTesting") { fixturePath in
            do {
                let (stdout, _) = try await execute(["--enable-swift-testing", "--disable-xctest"], packagePath: fixturePath)
                XCTAssertMatch(stdout, .contains(#"Test "SOME TEST FUNCTION" started"#))
            }
        }
    }

    func testBasicSwiftTestingIntegration_ExperimentalFlag() async throws {
#if !canImport(TestingDisabled)
        try XCTSkipUnless(
            nil != Environment.current["SWIFT_PM_SWIFT_TESTING_TESTS_ENABLED"],
            "Skipping \(#function) because swift-testing tests are not explicitly enabled"
        )
#endif

        try await fixture(name: "Miscellaneous/TestDiscovery/SwiftTesting") { fixturePath in
            do {
                let (stdout, _) = try await execute(["--enable-experimental-swift-testing", "--disable-xctest"], packagePath: fixturePath)
                XCTAssertMatch(stdout, .contains(#"Test "SOME TEST FUNCTION" started"#))
            }
        }
    }

#if !canImport(Darwin)
    func testGeneratedMainIsConcurrencySafe_XCTest() async throws {
        let strictConcurrencyFlags = ["-Xswiftc", "-strict-concurrency=complete"]
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try await execute(strictConcurrencyFlags, packagePath: fixturePath)
            XCTAssertNoMatch(stderr, .contains("is not concurrency-safe"))
        }
    }
#endif

#if !canImport(Darwin)
    func testGeneratedMainIsExistentialAnyClean() async throws {
        let existentialAnyFlags = ["-Xswiftc", "-enable-upcoming-feature", "-Xswiftc", "ExistentialAny"]
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try await execute(existentialAnyFlags, packagePath: fixturePath)
            XCTAssertNoMatch(stderr, .contains("error: use of protocol"))
        }
    }
#endif

    func testLibraryEnvironmentVariable() async throws {
        try await fixture(name: "Miscellaneous/CheckTestLibraryEnvironmentVariable") { fixturePath in
            var extraEnv = Environment()
            if try UserToolchain.default.swiftTestingPath != nil {
              extraEnv["CONTAINS_SWIFT_TESTING"] = "1"
            }
            await XCTAssertAsyncNoThrow(try await SwiftPM.Test.execute(packagePath: fixturePath, env: extraEnv))
        }
    }

    func testXCTestOnlyDoesNotLogAboutNoMatchingTests() async throws {
        try await fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try await execute(["--disable-swift-testing"], packagePath: fixturePath)
            XCTAssertNoMatch(stderr, .contains("No matching test cases were run"))
        }
    }

    func testFatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation() async throws {
        try XCTSkipIfCI()
        // Test for GitHub Issue #6605
        // GIVEN we have a Swift Package that has a fatalError building the tests
        let expected = 1
        try await fixture(name: "Miscellaneous/Errors/FatalErrorInSingleXCTest/TypeLibrary") { fixturePath in
            // WHEN swift-test is executed
            await XCTAssertAsyncThrowsError(try await self.execute([], packagePath: fixturePath)) { error in
                // THEN I expect a failure
                guard case SwiftPMError.executionFailure(_, let stdout, let stderr) = error else {
                    XCTFail("Building the package was expected to fail, but it was successful")
                    return
                }

                let matchString = "error: fatalError"
                let stdoutMatches = getNumberOfMatches(of: matchString, in: stdout)
                let stderrMatches = getNumberOfMatches(of: matchString, in: stderr)
                let actualNumMatches = stdoutMatches + stderrMatches

                // AND a fatal error message is printed \(expected) times
                XCTAssertEqual(
                    actualNumMatches,
                    expected,
                    [
                        "Actual (\(actualNumMatches)) is not as expected (\(expected))",
                        "stdout: \(stdout.debugDescription)",
                        "stderr: \(stderr.debugDescription)"
                    ].joined(separator: "\n")
                )
            }
        }
    }

}

class TestCommandNativeTests: TestCommandTestCase {
    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .native
    }

    override func testUsage() async throws {
        try await super.testUsage()
    }
}


class TestCommandSwiftBuildTests: TestCommandTestCase {
    override open var buildSystemProvider: BuildSystemProvider.Kind {
        return .swiftbuild
    }

    override func testUsage() async throws {
        try await super.testUsage()
    }

    override func testFatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTPM_NO_SWBUILD_DEPENDENCY"] == nil else {
            throw XCTSkip("Skipping test because SwiftBuild is not linked in.")
        }

        try await super.testFatalErrorDisplayedCorrectNumberOfTimesWhenSingleXCTestHasFatalErrorInBuildCompilation()
    }

    override func testListWithSkipBuildAndNoBuildArtifacts() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTPM_NO_SWBUILD_DEPENDENCY"] == nil else {
            throw XCTSkip("Skipping test because SwiftBuild is not linked in.")
        }

        try await super.testListWithSkipBuildAndNoBuildArtifacts()
    }

    override func testList() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails due to 'error: build failed'")
    }

    override func testEnableTestDiscoveryDeprecation() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails due to 'error: build failed'")
    }

    override func testEnableDisableTestability() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails due to 'error: build failed'")
    }

    override func testToolsetRunner() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails, as some assertions are not met")
    }

    override func testWithReleaseConfiguration() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails with 'error: toolchain is invalid: could not find CLI tool `swiftpm-testing-helper` at any of these directories: [..., ...]'")
    }

    override func testXCTestOnlyDoesNotLogAboutNoMatchingTests() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails assertion as the there is a different error message 'error: no tests found; create a target in the 'Tests' directory'")
    }

    override func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagEnabledSwiftTesting() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails assertion as the there is a different error message 'error: no tests found; create a target in the 'Tests' directory'")
    }

    override func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagDisabledSwiftTesting() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails, further investigation is needed")
    }

    override func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagEnabledSwiftTesting() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails, further investigation is needed")
    }

    override func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagDisabledSwiftTesting() async throws {
        throw XCTSkip("SWBINTTODO: Test currently fails, further investigation is needed")
    }

#if !canImport(Darwin)
    override func testGeneratedMainIsExistentialAnyClean() async throws {
        throw XCTSkip("SWBINTTODO: This is a PIF builder missing GUID problem. Further investigation is needed.")
    }
#endif

#if !canImport(Darwin)
    override func testGeneratedMainIsConcurrencySafe_XCTest() async throws {
        throw XCTSkip("SWBINTTODO: This is a PIF builder missing GUID problem. Further investigation is needed.")
    }
#endif

#if !os(macOS)
    override func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagDisabledXCTest() async throws {
        throw XCTSkip("Result XML could not be found. The build fails due to an LD_LIBRARY_PATH issue finding swift core libraries. https://github.com/swiftlang/swift-package-manager/issues/8416")
    }

    override func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagEnabledXCTest() async throws {
        throw XCTSkip("Result XML could not be found. The build fails due to an LD_LIBRARY_PATH issue finding swift core libraries. https://github.com/swiftlang/swift-package-manager/issues/8416")
    }

    override func testSwiftTestXMLOutputVerifySingleTestFailureMessageWithFlagEnabledXCTest() async throws {
        throw XCTSkip("Result XML could not be found. The build fails due to an LD_LIBRARY_PATH issue finding swift core libraries. https://github.com/swiftlang/swift-package-manager/issues/8416")
    }

    override func testSwiftTestXMLOutputVerifyMultipleTestFailureMessageWithFlagDisabledXCTest() async throws {
        throw XCTSkip("Result XML could not be found. The build fails due to an LD_LIBRARY_PATH issue finding swift core libraries. https://github.com/swiftlang/swift-package-manager/issues/8416")
    }

    override func testSwiftTestSkip() async throws {
        throw XCTSkip("This fails due to a linker error on Linux. https://github.com/swiftlang/swift-package-manager/issues/8439")
    }

    override func testSwiftTestXMLOutputWhenEmpty() async throws {
        throw XCTSkip("This fails due to a linker error on Linux. https://github.com/swiftlang/swift-package-manager/issues/8439")
    }

    override func testSwiftTestFilter() async throws {
        throw XCTSkip("This fails due to an unknown linker error on Linux. https://github.com/swiftlang/swift-package-manager/issues/8439")
    }

    override func testSwiftTestParallel() async throws {
        throw XCTSkip("This fails due to an unknown linker error on Linux. https://github.com/swiftlang/swift-package-manager/issues/8439")
    }
#endif
}
