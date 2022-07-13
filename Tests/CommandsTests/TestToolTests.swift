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

import Commands
import PackageModel
import SPMTestSupport
import TSCBasic
import XCTest

final class TestToolTests: CommandsTestCase {
    
    private func execute(_ args: [String], packagePath: AbsolutePath? = nil) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftTest.execute(args, packagePath: packagePath)
    }
    
    func testUsage() throws {
        let stdout = try execute(["-help"]).stdout
        XCTAssert(stdout.contains("USAGE: swift test"), "got stdout:\n" + stdout)
    }

    func testSeeAlso() throws {
        let stdout = try execute(["--help"]).stdout
        XCTAssert(stdout.contains("SEE ALSO: swift build, swift run, swift package"), "got stdout:\n" + stdout)
    }

    func testVersion() throws {
        let stdout = try execute(["--version"]).stdout
        XCTAssert(stdout.contains("Swift Package Manager"), "got stdout:\n" + stdout)
    }

    func testNumWorkersParallelRequirement() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            XCTAssertThrowsCommandExecutionError(try execute(["--num-workers", "1"])) { error in
                XCTAssertMatch(error.stderr, .contains("error: --num-workers must be used with --parallel"))
            }
        }
    }
    
    func testNumWorkersValue() throws {
        #if !os(macOS)
        // Running swift-test fixtures on linux is not yet possible.
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/EchoExecutable") { fixturePath in
            XCTAssertThrowsCommandExecutionError(try execute(["--parallel", "--num-workers", "0"])) { error in
                XCTAssertMatch(error.stderr, .contains("error: '--num-workers' must be greater than zero"))
            }
        }
    }

    func testEnableDisableTestability() throws {
        // default should run with testability
        try fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try execute(["--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }

        // disabled
        try fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            XCTAssertThrowsCommandExecutionError( try execute(["--disable-testable-imports", "--vv"], packagePath: fixturePath)) { error in
                XCTAssertMatch(error.stderr, .contains("was not compiled for testing"))
            }
        }

        // enabled
        try fixture(name: "Miscellaneous/TestableExe") { fixturePath in
            do {
                let result = try execute(["--enable-testable-imports", "--vv"], packagePath: fixturePath)
                XCTAssertMatch(result.stderr, .contains("-enable-testing"))
            }
        }
    }

    func testSwiftTestParallel() throws {
        try fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            // First try normal serial testing.
            XCTAssertThrowsCommandExecutionError(try SwiftPMProduct.SwiftTest.execute([], packagePath: fixturePath)) { error in
                // in "swift test" test output goes to stdout
                XCTAssertMatch(error.stdout, .contains("Executed 2 tests"))
            }

            // Run tests in parallel.
            XCTAssertThrowsCommandExecutionError(try SwiftPMProduct.SwiftTest.execute(["--parallel"], packagePath: fixturePath)) { error in
                // in "swift test" test output goes to stdout
                XCTAssertMatch(error.stdout, .contains("testExample1"))
                XCTAssertMatch(error.stdout, .contains("testExample2"))
                XCTAssertNoMatch(error.stdout, .contains("'ParallelTestsTests' passed"))
                XCTAssertMatch(error.stdout, .contains("'ParallelTestsFailureTests' failed"))
                XCTAssertMatch(error.stdout, .contains("[3/3]"))
            }

            do {
                let xUnitOutput = fixturePath.appending(component: "result.xml")
                // Run tests in parallel with verbose output.
                XCTAssertThrowsCommandExecutionError(
                    try SwiftPMProduct.SwiftTest.execute(["--parallel", "--verbose", "--xunit-output", xUnitOutput.pathString], packagePath: fixturePath)
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

    func testSwiftTestFilter() throws {
        try fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            let result = try SwiftPMProduct.SwiftTest.executeProcess(["--filter", ".*1"], packagePath: fixturePath)
            let stdout = try result.utf8Output()
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testSureFailure"))
        }

        try fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            let result = try SwiftPMProduct.SwiftTest.executeProcess(["--filter", "ParallelTestsTests", "--skip", ".*1", "--filter", "testSureFailure"], packagePath: fixturePath)
            let stdout = try result.utf8Output()
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertMatch(stdout, .contains("testExample2"))
            XCTAssertMatch(stdout, .contains("testSureFailure"))
        }
    }

    func testSwiftTestSkip() throws {
        try fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            let result = try SwiftPMProduct.SwiftTest.executeProcess(["--skip", "ParallelTestsTests"], packagePath: fixturePath)
            let stdout = try result.utf8Output()
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertMatch(stdout, .contains("testSureFailure"))
        }

        try fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            let result = try SwiftPMProduct.SwiftTest.executeProcess(["--filter", "ParallelTestsTests", "--skip", ".*2", "--filter", "TestsFailure", "--skip", "testSureFailure"], packagePath: fixturePath)
            let stdout = try result.utf8Output()
            // in "swift test" test output goes to stdout
            XCTAssertMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testSureFailure"))
        }

        try fixture(name: "Miscellaneous/ParallelTestsPkg") { fixturePath in
            let result = try SwiftPMProduct.SwiftTest.executeProcess(["--skip", "Tests"], packagePath: fixturePath)
            let stdout = try result.utf8Output()
            let stderr = try result.utf8stderrOutput()
            // in "swift test" test output goes to stdout
            XCTAssertNoMatch(stdout, .contains("testExample1"))
            XCTAssertNoMatch(stdout, .contains("testExample2"))
            XCTAssertNoMatch(stdout, .contains("testSureFailure"))
            XCTAssertMatch(stderr, .contains("No matching test cases were run"))
        }
    }

    func testEnableTestDiscoveryDeprecation() throws {
        let compilerDiagnosticFlags = ["-Xswiftc", "-Xfrontend", "-Xswiftc", "-Rmodule-interface-rebuild"]
        #if canImport(Darwin)
        // should emit when LinuxMain is present
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try SwiftPMProduct.SwiftTest.execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }

        // should emit when LinuxMain is not present
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            try localFileSystem.writeFileContents(fixturePath.appending(components: "Tests", SwiftTarget.testManifestNames.first!), bytes: "fatalError(\"boom\")")
            let (_, stderr) = try SwiftPMProduct.SwiftTest.execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }
        #else
        // should emit when LinuxMain is present
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try SwiftPMProduct.SwiftTest.execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }
        // should not emit when LinuxMain is present
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            try localFileSystem.writeFileContents(fixturePath.appending(components: "Tests", SwiftTarget.testManifestNames.first!), bytes: "fatalError(\"boom\")")
            let (_, stderr) = try SwiftPMProduct.SwiftTest.execute(["--enable-test-discovery"] + compilerDiagnosticFlags, packagePath: fixturePath)
            XCTAssertNoMatch(stderr, .contains("warning: '--enable-test-discovery' option is deprecated"))
        }
        #endif
    }

    func testGenerateLinuxMainDeprecation() throws {
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            let (_, stderr) = try SwiftPMProduct.SwiftTest.execute(["--generate-linuxmain"], packagePath: fixturePath)
            // test deprecation warning
            XCTAssertMatch(stderr, .contains("warning: '--generate-linuxmain' option is deprecated"))
        }
    }

    func testGenerateLinuxMain() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try fixture(name: "Miscellaneous/TestDiscovery/Simple") { fixturePath in
            _ = try SwiftPMProduct.SwiftTest.execute(["--generate-linuxmain"], packagePath: fixturePath)

            // Check LinuxMain
            let linuxMain = fixturePath.appending(components: "Tests", "LinuxMain.swift")
             XCTAssertEqual(try localFileSystem.readFileContents(linuxMain), """
                 import XCTest

                 import SimpleTests

                 var tests = [XCTestCaseEntry]()
                 tests += SimpleTests.__allTests()

                 XCTMain(tests)

                 """)

            // Check test manifest
            let testManifest = fixturePath.appending(components: "Tests", "SimpleTests", "XCTestManifests.swift")
            XCTAssertEqual(try localFileSystem.readFileContents(testManifest), """
                #if !canImport(ObjectiveC)
                import XCTest

                extension SimpleTests {
                    // DO NOT MODIFY: This is autogenerated, use:
                    //   `swift test --generate-linuxmain`
                    // to regenerate.
                    static let __allTests__SimpleTests = [
                        ("test_Example2", test_Example2),
                        ("testExample1", testExample1),
                        ("testThrowing", testThrowing),
                    ]
                }

                public func __allTests() -> [XCTestCaseEntry] {
                    return [
                        testCase(SimpleTests.__allTests__SimpleTests),
                    ]
                }
                #endif

                """)
        }
    }
}
