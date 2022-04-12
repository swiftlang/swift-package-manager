/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TSCBasic
import TSCTestSupport

final class BasicTests: XCTestCase {
    func testVersion() throws {
        XCTAssertMatch(try sh(swift, "--version").stdout, .contains("Swift version"))
    }

    func testExamplePackageDealer() throws {
        try XCTSkipIf(isSelfHosted, "These packages don't use the latest runtime library, which doesn't work with self-hosted builds.")

        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "dealer")
            try sh("git", "clone", "https://github.com/apple/example-package-dealer", packagePath)
            let build1Output = try sh(swiftBuild, "--package-path", packagePath).stdout
            // Check the build log.
            XCTAssertMatch(build1Output, .contains("Build complete"))

            // Verify that the app works.
            let dealerOutput = try sh(AbsolutePath(".build/debug/dealer", relativeTo: packagePath), "10").stdout
            XCTAssertEqual(dealerOutput.filter(\.isPlayingCardSuit).count, 10)

            // Verify that the 'git status' is clean after a build.
            try localFileSystem.changeCurrentWorkingDirectory(to: packagePath)
            let gitOutput = try sh("git", "status").stdout
            XCTAssertMatch(gitOutput, .contains("nothing to commit, working tree clean"))

            // Verify that another 'swift build' does nothing.
            let build2Output = try sh(swiftBuild, "--package-path", packagePath).stdout
            XCTAssertMatch(build2Output, .contains("Build complete"))
            XCTAssertNoMatch(build2Output, .contains("Compiling"))
        }
    }

    func testSwiftBuild() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "tool")
            try localFileSystem.createDirectory(packagePath)
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "Package.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    // swift-tools-version:4.2
                    import PackageDescription

                    let package = Package(
                        name: "tool",
                        targets: [
                            .target(name: "tool", path: "./"),
                        ]
                    )
                    """))
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "main.swift"),
                bytes: ByteString(encodingAsUTF8: #"print("HI")"#))

            // Check the build.
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath, "-v").stdout
            XCTAssertMatch(buildOutput, .regex("swiftc.* -module-name tool"))

            // Verify that the tool exists and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "tool")).stdout
            XCTAssertEqual(toolOutput, "HI\n")
        }
    }

    func testSwiftCompiler() throws {
        try withTemporaryDirectory { tempDir in
            let helloSourcePath = tempDir.appending(component: "hello.swift")
            try localFileSystem.writeFileContents(
                helloSourcePath,
                bytes: ByteString(encodingAsUTF8: #"print("hello")"#))
            let helloBinaryPath = tempDir.appending(component: "hello")
            try sh(swiftc, helloSourcePath, "-o", helloBinaryPath)

            // Check the file exists.
            XCTAssert(localFileSystem.exists(helloBinaryPath))

            // Check the file runs.
            let helloOutput = try sh(helloBinaryPath).stdout
            XCTAssertEqual(helloOutput, "hello\n")
        }
    }

    func testSwiftPackageInitExec() throws {
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath).stdout

            // Check the build log.
            XCTAssertContents(buildOutput) { checker in
                checker.check(.regex("Compiling .*Project.*"))
                checker.check(.regex("Linking .*Project"))
                checker.check(.contains("Build complete"))
            }

            // Verify that the tool was built and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "Project")).stdout
            XCTAssertMatch(toolOutput.lowercased(), .contains("hello, world!"))

            // Check there were no compile errors or warnings.
            XCTAssertNoMatch(buildOutput, .contains("error"))
            XCTAssertNoMatch(buildOutput, .contains("warning"))
        }
    }

    func testSwiftPackageInitExecTests() throws {
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        try XCTSkip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")

        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            let testOutput = try sh(swiftTest, "--package-path", packagePath).stdout

            // Check the test log.
            XCTAssertContents(testOutput) { checker in
                checker.check(.regex("Compiling .*ProjectTests.*"))
                checker.check("Test Suite 'All tests' passed")
                checker.checkNext("Executed 1 test")
            }

            // Check there were no compile errors or warnings.
            XCTAssertNoMatch(testOutput, .contains("error"))
            XCTAssertNoMatch(testOutput, .contains("warning"))
        }
    }

    func testSwiftPackageInitLib() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath).stdout

            // Check the build log.
            XCTAssertMatch(buildOutput, .regex("Compiling .*Project.*"))
            XCTAssertMatch(buildOutput, .contains("Build complete"))

            // Check there were no compile errors or warnings.
            XCTAssertNoMatch(buildOutput, .contains("error"))
            XCTAssertNoMatch(buildOutput, .contains("warning"))
        }
    }

    func testSwiftPackageLibsTests() throws {
        try XCTSkip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")

        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            let testOutput = try sh(swiftTest, "--package-path", packagePath).stdout

            // Check the test log.
            XCTAssertContents(testOutput) { checker in
                checker.check(.regex("Compiling .*ProjectTests.*"))
                checker.check("Test Suite 'All tests' passed")
                checker.checkNext("Executed 1 test")
            }

            // Check there were no compile errors or warnings.
            XCTAssertNoMatch(testOutput, .contains("error"))
            XCTAssertNoMatch(testOutput, .contains("warning"))
        }
    }

    func testSwiftPackageWithSpaces() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(components: "more spaces", "special tool")
            try localFileSystem.createDirectory(packagePath, recursive: true)
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "Package.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    // swift-tools-version:4.2
                    import PackageDescription

                    let package = Package(
                       name: "special tool",
                       targets: [
                           .target(name: "special tool", path: "./"),
                       ]
                    )
                    """))
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "main.swift"),
                bytes: ByteString(encodingAsUTF8: #"foo()"#))
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "some file.swift"),
                bytes: ByteString(encodingAsUTF8: #"func foo() { print("HI") }"#))

            // Check the build.
            let buildOutput = try sh(swiftBuild, "--package-path", packagePath, "-v").stdout
            XCTAssertMatch(buildOutput, .regex(#"swiftc.* -module-name special_tool .* ".*/more spaces/special tool/some file.swift""#))
            XCTAssertMatch(buildOutput, .contains("Build complete"))

            // Verify that the tool exists and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "special tool")).stdout
            XCTAssertEqual(toolOutput, "HI\n")
        }
    }

    func testSwiftRun() throws {
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "secho")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "executable")
            // delete any files generated
            for entry in try localFileSystem.getDirectoryContents(packagePath.appending(components: "Sources", "secho")) {
                try localFileSystem.removeFileTree(packagePath.appending(components: "Sources", "secho", entry))
            }
            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Sources", "secho", "main.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    import Foundation
                    print(CommandLine.arguments.dropFirst().joined(separator: " "))
                    """))
            let (runOutput, runError) = try sh(swiftRun, "--package-path", packagePath, "secho", "1", #""two""#)

            // Check the run log.
            XCTAssertContents(runError) { checker in
                checker.check(.regex("Compiling .*secho.*"))
                checker.check(.regex("Linking .*secho"))
                checker.check(.contains("Build complete"))
            }
            XCTAssertEqual(runOutput, "1 \"two\"\n")
        }
    }

    func testSwiftTest() throws {
        try XCTSkip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")

        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "swiftTest")
            try localFileSystem.createDirectory(packagePath)
            try sh(swiftPackage, "--package-path", packagePath, "init", "--type", "library")
            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Tests", "swiftTestTests", "MyTests.swift"),
                bytes: ByteString(encodingAsUTF8: """
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
                    """))
            let testOutput = try sh(swiftTest, "--package-path", packagePath, "--filter", "MyTests.*", "--skip", "testBaz").stderr

            // Check the test log.
            XCTAssertContents(testOutput) { checker in
                checker.check(.contains("Test Suite 'MyTests' started"))
                checker.check(.contains("Test Suite 'MyTests' passed"))
                checker.check(.contains("Executed 2 tests, with 0 failures"))
            }
        }
    }

    func testSwiftTestWithResources() throws {
        try XCTSkip("FIXME: swift-test invocations are timing out in Xcode and self-hosted CI")

        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "swiftTestResources")
            try localFileSystem.createDirectory(packagePath)
            try localFileSystem.writeFileContents(
                packagePath.appending(component: "Package.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    // swift-tools-version:5.3
                    import PackageDescription

                    let package = Package(
                       name: "AwesomeResources",
                       targets: [
                           .target(name: "AwesomeResources", resources: [.copy("hello.txt")]),
                           .testTarget(name: "AwesomeResourcesTest", dependencies: ["AwesomeResources"], resources: [.copy("world.txt")])
                       ]
                    )
                    """)
            )
            try localFileSystem.createDirectory(packagePath.appending(component: "Sources"))
            try localFileSystem.createDirectory(packagePath.appending(components: "Sources", "AwesomeResources"))
            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Sources", "AwesomeResources", "AwesomeResource.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    import Foundation

                    public struct AwesomeResource {
                      public init() {}
                      public let hello = try! String(contentsOf: Bundle.module.url(forResource: "hello", withExtension: "txt")!)
                    }

                    """)
            )

            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Sources", "AwesomeResources", "hello.txt"),
                bytes: ByteString(encodingAsUTF8: "hello")
            )

            try localFileSystem.createDirectory(packagePath.appending(component: "Tests"))
            try localFileSystem.createDirectory(packagePath.appending(components: "Tests", "AwesomeResourcesTest"))

            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Tests", "AwesomeResourcesTest", "world.txt"),
                bytes: ByteString(encodingAsUTF8: "world")
            )

            try localFileSystem.writeFileContents(
                packagePath.appending(components: "Tests", "AwesomeResourcesTest", "MyTests.swift"),
                bytes: ByteString(encodingAsUTF8: """
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
                    """))

            let testOutput = try sh(swiftTest, "--package-path", packagePath, "--filter", "MyTests.*").stderr

            // Check the test log.
            XCTAssertContents(testOutput) { checker in
                checker.check(.contains("Test Suite 'MyTests' started"))
                checker.check(.contains("Test Suite 'MyTests' passed"))
                checker.check(.contains("Executed 2 tests, with 0 failures"))
            }
        }
    }
}

private extension Character {
    var isPlayingCardSuit: Bool {
        switch self {
        case "♠︎", "♡", "♢", "♣︎":
            return true
        default:
            return false
        }
    }
}
