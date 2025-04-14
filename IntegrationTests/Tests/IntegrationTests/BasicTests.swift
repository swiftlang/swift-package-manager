/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import IntegrationTestSupport
import Testing
import TSCBasic
import TSCTestSupport
@Suite
private struct BasicTests {
    @Test(
        .skipHostOS(.windows,  "'try!' expression unexpectedly raised an error: TSCBasic.Process.Error.missingExecutableProgram(program: \"which\")")
    )
    func testVersion() throws {
        #expect(try sh(swift, "--version").stdout.contains("Swift version"))
    }

    @Test(
        .skipSwiftCISelfHosted(
            "These packages don't use the latest runtime library, which doesn't work with self-hosted builds."
        ),
        .requireUnrestrictedNetworkAccess("Test requires access to https://github.com"),
        .skipHostOS(.windows, "Issue #8409 - random.swift:34:8: error: unsupported platform")
    )
    func testExamplePackageDealer() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "dealer")
            try sh("git\(ProcessInfo.exeSuffix)", "clone", "https://github.com/apple/example-package-dealer", packagePath)
            let build1Output = try sh(swiftBuild, "--package-path", packagePath).stdout

            // Check the build log.
            #expect(build1Output.contains("Build complete"))

            // Verify that the app works.
            let dealerOutput = try sh(
                AbsolutePath(validating: ".build/debug/dealer", relativeTo: packagePath), "10"
            ).stdout
            #expect(dealerOutput.filter(\.isPlayingCardSuit).count == 10)

            // Verify that the 'git status' is clean after a build.
            try localFileSystem.changeCurrentWorkingDirectory(to: packagePath)
            let gitOutput = try sh("git\(ProcessInfo.exeSuffix)", "status").stdout
            #expect(gitOutput.contains("nothing to commit, working tree clean"))

            // Verify that another 'swift build' does nothing.
            let build2Output = try sh(swiftBuild, "--package-path", packagePath).stdout
            #expect(build2Output.contains("Build complete"))
            #expect(build2Output.contains("Compiling") == false)
        }
    }

    @Test
    func testSwiftBuild() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "tool")
            try localFileSystem.createDirectory(packagePath)
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "Package.swift"),
                bytes: ByteString(
                    encodingAsUTF8: """
                    // swift-tools-version:4.2
                    import PackageDescription

                    let package = Package(
                        name: "tool",
                        targets: [
                            .target(name: "tool", path: "./"),
                        ]
                    )
                    """
                )
            )
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "main.swift"),
                bytes: ByteString(encodingAsUTF8: #"print("HI")"#)
            )

            // Check the build.
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath, "-v").stdout
            #expect(try #/swiftc.* -module-name tool/#.firstMatch(in: buildOutput) != nil)

            // Verify that the tool exists and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "tool"))
                .stdout
            #expect(toolOutput == "HI\(ProcessInfo.EOL)")
        }
    }

    @Test(
        .skipHostOS(.windows, "'try!' expression unexpectedly raised an error: TSCBasic.Process.Error.missingExecutableProgram(program: \"which\")")
    )
    func testSwiftCompiler() throws {
        try withTemporaryDirectory { tempDir in
            let helloSourcePath = tempDir.appending(component: "hello.swift")
            try localFileSystem.writeFileContents(
                helloSourcePath,
                bytes: ByteString(encodingAsUTF8: #"print("hello")"#)
            )
            let helloBinaryPath = tempDir.appending(component: "hello")
            try sh(swiftc, helloSourcePath, "-o", helloBinaryPath)

            // Check the file exists.
            #expect(localFileSystem.exists(helloBinaryPath))

            // Check the file runs.
            let helloOutput = try sh(helloBinaryPath).stdout
            #expect(helloOutput == "hello\(ProcessInfo.EOL)")
        }
    }

    @Test(
        .skipHostOS(.windows, "failed to build package")
    )
    func testSwiftPackageInitExec() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath).stdout

            // Check the build log.
            let checker = StringChecker(string: buildOutput)
            #expect(checker.check(.regex("Compiling .*Project.*")))
            #expect(checker.check(.regex("Linking .*Project")))
            #expect(checker.check(.contains("Build complete")))

            // Verify that the tool was built and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "Project"))
                .stdout
            #expect(toolOutput.lowercased().contains("hello, world!"))

            // Check there were no compile errors or warnings.
            #expect(buildOutput.contains("error") == false)
            #expect(buildOutput.contains("warning") == false)
        }
    }

    @Test
    func testSwiftPackageInitExecTests() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            withKnownIssue("error: no tests found; create a target in the 'Tests' directory") {
                try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
                let testOutput = try sh(swiftTest, "--package-path", packagePath).stdout

                // Check the test log.
                let checker = StringChecker(string: testOutput)
                #expect(checker.check(.regex("Compiling .*ProjectTests.*")))
                #expect(checker.check("Test Suite 'All tests' passed"))
                #expect(checker.checkNext("Executed 1 test"))

                // Check there were no compile errors or warnings.
                #expect(testOutput.contains("error") == false)
                #expect(testOutput.contains("warning") == false)
            }
        }
    }

    @Test
    func testSwiftPackageInitLib() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath).stdout

            // Check the build log.
            #expect(try #/Compiling .*Project.*/#.firstMatch(in: buildOutput) != nil)
            #expect(buildOutput.contains("Build complete"))

            // Check there were no compile errors or warnings.
            #expect(buildOutput.contains("error") == false)
            #expect(buildOutput.contains("warning") == false)
        }
    }

    @Test
    func testSwiftPackageLibsTests() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            let testOutput = try sh(swiftTest, "--package-path", packagePath).stdout

            // Check the test log.
            let checker = StringChecker(string: testOutput)
            #expect(checker.check(.contains("Test Suite 'All tests' started")))
            #expect(checker.check(.contains("Test example() passed after")))
            #expect(checker.checkNext(.contains("Test run with 1 test passed after")))

            // Check there were no compile errors or warnings.
            #expect(testOutput.contains("error") == false)
            #expect(testOutput.contains("warning") == false)
        }
    }

    @Test(
        .skipHostOS(.windows, "unexpected failure matching")
    )
    func testSwiftPackageWithSpaces() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(components: "more spaces", "special tool")
            try localFileSystem.createDirectory(packagePath, recursive: true)
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "Package.swift"),
                bytes: ByteString(
                    encodingAsUTF8: """
                    // swift-tools-version:4.2
                    import PackageDescription

                    let package = Package(
                       name: "special tool",
                       targets: [
                           .target(name: "special tool", path: "./"),
                       ]
                    )
                    """
                )
            )
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "main.swift"),
                bytes: ByteString(encodingAsUTF8: #"foo()"#)
            )
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "some file.swift"),
                bytes: ByteString(encodingAsUTF8: #"func foo() { print("HI") }"#)
            )

            // Check the build.
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath, "-v").stdout
            let expression = ProcessInfo
                .hostOperatingSystem != .windows ?
                #/swiftc.* -module-name special_tool .* '@.*/more spaces/special tool/.build/[^/]+/debug/special_tool.build/sources'/# :
                #/swiftc.* -module-name special_tool .* "@.*\\more spaces\\special tool\\.build\\[^\\]+\\debug\\special_tool.build\\sources"/#
            #expect(try expression.firstMatch(in: buildOutput) != nil)
            #expect(buildOutput.contains("Build complete"))

            // Verify that the tool exists and works.
            let toolOutput = try sh(
                packagePath.appending(components: ".build", "debug", "special tool")
            ).stdout

            #expect(toolOutput == "HI\(ProcessInfo.EOL)")
        }
    }

    @Test(
        .skipHostOS(.windows, "package fails to build")
    )
    func testSwiftRun() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "secho")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            // delete any files generated
            for entry in try localFileSystem.getDirectoryContents(
                packagePath.appending(components: "Sources")
            ) {
                try localFileSystem.removeFileTree(
                    packagePath.appending(components: "Sources", entry)
                )
            }
            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Sources", "secho.swift"),
                bytes: ByteString(
                    encodingAsUTF8: """
                    import Foundation
                    print(CommandLine.arguments.dropFirst().joined(separator: " "))
                    """
                )
            )
            let (runOutput, runError) = try sh(
                swiftRun, "--package-path", packagePath, "secho", "1", #""two""#
            )

            // Check the run log.
            let checker = StringChecker(string: runError)
            #expect(checker.check(.regex("Compiling .*secho.*")))
            #expect(checker.check(.regex("Linking .*secho")))
            #expect(checker.check(.contains("Build of product 'secho' complete")))

            #expect(runOutput == "1 \"two\"\(ProcessInfo.EOL)")
        }
    }

    func testSwiftTest() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "swiftTest")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Tests", "swiftTestTests", "MyTests.swift"),
                bytes: ByteString(
                    encodingAsUTF8: """
                    import XCTest

                    final class MyTests: XCTestCase {
                        func testFoo() {
                            XCTAssertTrue(1 == 1)
                        }
                        func testBar() {
                            XCTAssertFalse(1 == 2)
                        }
                        func testBaz() { }
                    }
                    """
                )
            )
            let testOutput = try sh(
                swiftTest, "--package-path", packagePath, "--filter", "MyTests.*", "--skip",
                "testBaz"
            ).stderr

            // Check the test log.
            let checker = StringChecker(string: testOutput)
            #expect(checker.check(.contains("Test Suite 'MyTests' started")))
            #expect(checker.check(.contains("Test Suite 'MyTests' passed")))
            #expect(checker.check(.contains("Executed 2 tests, with 0 failures")))
        }
    }

    @Test
    func testSwiftTestWithResources() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "swiftTestResources")
            try localFileSystem.createDirectory(packagePath)
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "Package.swift"),
                bytes: ByteString(
                    encodingAsUTF8: """
                    // swift-tools-version:5.3
                    import PackageDescription

                    let package = Package(
                       name: "AwesomeResources",
                       targets: [
                           .target(name: "AwesomeResources", resources: [.copy("hello.txt")]),
                           .testTarget(name: "AwesomeResourcesTest", dependencies: ["AwesomeResources"], resources: [.copy("world.txt")])
                       ]
                    )
                    """
                )
            )
            try localFileSystem.createDirectory(packagePath.appending(component: "Sources"))
            try localFileSystem.createDirectory(
                packagePath.appending(components: "Sources", "AwesomeResources")
            )
            try localFileSystem.writeFileContents(
                packagePath.appending(
                    components: "Sources", "AwesomeResources", "AwesomeResource.swift"
                ),
                bytes: ByteString(
                    encodingAsUTF8: """
                    import Foundation

                    public struct AwesomeResource {
                      public init() {}
                      public let hello = try! String(contentsOf: Bundle.module.url(forResource: "hello", withExtension: "txt")!)
                    }

                    """
                )
            )

            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Sources", "AwesomeResources", "hello.txt"),
                bytes: ByteString(encodingAsUTF8: "hello")
            )

            try localFileSystem.createDirectory(packagePath.appending(component: "Tests"))
            try localFileSystem.createDirectory(
                packagePath.appending(components: "Tests", "AwesomeResourcesTest")
            )

            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Tests", "AwesomeResourcesTest", "world.txt"),
                bytes: ByteString(encodingAsUTF8: "world")
            )

            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Tests", "AwesomeResourcesTest", "MyTests.swift"),
                bytes: ByteString(
                    encodingAsUTF8: """
                    import XCTest
                    import Foundation
                    import AwesomeResources

                    final class MyTests: XCTestCase {
                        func testFoo() {
                            XCTAssertTrue(AwesomeResource().hello == "hello")
                        }
                        func testBar() {
                            let world = try! String(contentsOf: Bundle.module.url(forResource: "world", withExtension: "txt")!)
                            XCTAssertTrue(world == "world")
                        }
                    }
                    """
                )
            )

            let testOutput = try sh(
                swiftTest, "--package-path", packagePath, "--filter", "MyTests.*"
            ).stdout

            // Check the test log.
            let checker = StringChecker(string: testOutput)
            #expect(checker.check(.contains("Test Suite 'MyTests' started")))
            #expect(checker.check(.contains("Test Suite 'MyTests' passed")))
            #expect(checker.check(.contains("Executed 2 tests, with 0 failures")))
        }
    }
}

extension Character {
    fileprivate var isPlayingCardSuit: Bool {
        switch self {
        case "♠︎", "♡", "♢", "♣︎":
            return true
        default:
            return false
        }
    }
}
