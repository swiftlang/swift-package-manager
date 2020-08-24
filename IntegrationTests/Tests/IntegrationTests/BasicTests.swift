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

    // Disabled because these packages don't use the latest runtime library which doesn't work with self-hosted builds.
    //
    // FIXME: We should to use XCTSkip to skip this test instead.
    func DISABLED_testExamplePackageDealer() throws {
        try withTemporaryDirectory { dir in
            let dealerDir = dir.appending(component: "dealer")
            try sh("git", "clone", "https://github.com/apple/example-package-dealer", dealerDir)
            let build1Output = try sh(swiftBuild, "--package-path", dealerDir).stdout

            // Check the build log.
            XCTAssertContents(build1Output) { checker in
                checker.check(.contains("Merging module FisherYates"))
                checker.check(.contains("Merging module Dealer"))
            }

            // Verify that the build worked.
            let dealerOutput = try sh(dealerDir.appending(RelativePath(".build/debug/Dealer"))).stdout
            XCTAssertMatch(dealerOutput, .regex("(?:(♡|♠|♢|♣)\\s([0-9JQKA]|10)\\n)+"))

            // Verify that the 'git status' is clean after a build.
            try localFileSystem.changeCurrentWorkingDirectory(to: dealerDir)
            let gitOutput = try sh("git", "status").stdout
            XCTAssertMatch(gitOutput, .contains("nothing to commit, working tree clean"))

            // Verify that another 'swift build' does nothing.
            let build2Output = try sh(swiftBuild, "--package-path", dealerDir).stdout
            XCTAssertNoMatch(build2Output, .contains("Compiling"))
        }
    }

    func testSwiftBuild() throws {
        try withTemporaryDirectory { dir in
            let toolDir = dir.appending(component: "tool")
            try localFileSystem.createDirectory(toolDir)
            try localFileSystem.writeFileContents(
                toolDir.appending(component: "Package.swift"),
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
                toolDir.appending(component: "main.swift"),
                bytes: ByteString(encodingAsUTF8: #"print("HI")"#))

            // Check the build.
            let buildOutput = try sh(swiftBuild, "--package-path", toolDir, "-v").stdout
            XCTAssertMatch(buildOutput, .regex("swiftc.* -module-name tool"))

            // Verify that the tool exists and works.
            let toolOutput = try sh(toolDir.appending(components: ".build", "debug", "tool")).stdout
            XCTAssertEqual(toolOutput, "HI\n")
        }
    }

    func testSwiftCompiler() throws {
        try withTemporaryDirectory { dir in
            let helloSourcePath = dir.appending(component: "hello.swift")
            try localFileSystem.writeFileContents(
                helloSourcePath,
                bytes: ByteString(encodingAsUTF8: #"print("hello")"#))
            let helloBinaryPath = dir.appending(component: "hello")
            try sh(swiftc, helloSourcePath, "-o", helloBinaryPath)

            // Check the file exists.
            XCTAssert(localFileSystem.exists(helloBinaryPath))

            // Check the file runs.
            let helloOutput = try sh(helloBinaryPath).stdout
            XCTAssertEqual(helloOutput, "hello\n")
        }
    }

    func testSwiftPackageInitExec() throws {
        try withTemporaryDirectory { dir in
            // Create a new package with an executable target.
            let projectDir = dir.appending(component: "Project")
            try localFileSystem.createDirectory(projectDir)
            try sh(swiftPackage, "--package-path", projectDir, "init", "--type", "executable")
            let buildOutput = try sh(swiftBuild, "--package-path", projectDir).stdout

            // Check the build log.
            XCTAssertContents(buildOutput) { checker in
                checker.check(.regex("Compiling .*Project.*"))
                checker.check(.regex("Linking .*Project"))
            }

            // Verify that the tool was built and works.
            let toolOutput = try sh(projectDir.appending(components: ".build", "debug", "Project")).stdout
            XCTAssertEqual(toolOutput, "Hello, world!\n")

            // Check there were no compile errors or warnings.
            XCTAssertNoMatch(buildOutput, .contains("error"))
            XCTAssertNoMatch(buildOutput, .contains("warning"))
        }
    }

    // TODO: Check why this test is failing to test in Xcode and through the command line.
    func _testSwiftPackageInitLib() throws {
        try withTemporaryDirectory { dir in
            // Create a new package with an executable target.
            let projectDir = dir.appending(component: "Project")
            try localFileSystem.createDirectory(projectDir)
            try sh(swiftPackage, "--package-path", projectDir, "init", "--type", "library")
            let buildOutput = try sh(swiftBuild, "--package-path", projectDir).stdout
            let testOutput = try sh(swiftTest, "--package-path", projectDir).stdout

            // Check the build log.
            XCTAssertMatch(buildOutput, .regex("Compiling .*Project.*"))

            // Check the test log.
            XCTAssertContents(testOutput) { checker in
                checker.check(.regex("Compiling .*ProjectTests.*"))
                checker.check("Test Suite 'All tests' passed")
                checker.checkNext("Executed 1 test")
            }

            // Check there were no compile errors or warnings.
            XCTAssertNoMatch(buildOutput, .contains("error"))
            XCTAssertNoMatch(buildOutput, .contains("warning"))
        }
    }

    func testSwiftPackageWithSpaces() throws {
        try withTemporaryDirectory { dir in
            let toolDir = dir.appending(components: "more spaces", "special tool")
            try localFileSystem.createDirectory(toolDir, recursive: true)
            try localFileSystem.writeFileContents(
                toolDir.appending(component: "Package.swift"),
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
                toolDir.appending(component: "main.swift"),
                bytes: ByteString(encodingAsUTF8: #"foo()"#))
            try localFileSystem.writeFileContents(
                toolDir.appending(component: "some file.swift"),
                bytes: ByteString(encodingAsUTF8: #"func foo() { print("HI") }"#))

            // Check the build.
            let buildOutput = try sh(swiftBuild, "--package-path", toolDir, "-v").stdout
            XCTAssertMatch(buildOutput, .regex(#"swiftc.* -module-name special_tool .* ".*/more spaces/special tool/some file.swift""#))

            // Verify that the tool exists and works.
            let toolOutput = try sh(toolDir.appending(components: ".build", "debug", "special tool")).stdout
            XCTAssertEqual(toolOutput, "HI\n")
        }
    }

    func testSwiftRun() throws {
        try withTemporaryDirectory { dir in
            let toolDir = dir.appending(component: "secho")
            try localFileSystem.createDirectory(toolDir)
            try sh(swiftPackage, "--package-path", toolDir, "init", "--type", "executable")
            try localFileSystem.writeFileContents(
                toolDir.appending(components: "Sources", "secho", "main.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    import Foundation
                    print(CommandLine.arguments.dropFirst().joined(separator: " "))
                    """))
            let (runOutput, runError) = try sh(swiftRun, "--package-path", toolDir, "secho", "1", #""two""#)

            // Check the run log.
            XCTAssertContents(runError) { checker in
                checker.check(.regex("Compiling .*secho.*"))
                checker.check(.regex("Linking .*secho"))
            }
            XCTAssertEqual(runOutput, "1 \"two\"\n")
        }
    }

    func testSwiftTest() throws {
        try withTemporaryDirectory { dir in
            let toolDir = dir.appending(component: "swiftTest")
            try localFileSystem.createDirectory(toolDir)
            try sh(swiftPackage, "--package-path", toolDir, "init", "--type", "library")
            try localFileSystem.writeFileContents(
                toolDir.appending(components: "Tests", "swiftTestTests", "MyTests.swift"),
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
            let testOutput = try sh(swiftTest, "--package-path", toolDir, "--filter", "MyTests.*", "--skip", "testBaz").stderr

            // Check the test log.
            XCTAssertContents(testOutput) { checker in
                checker.check(.contains("Test Suite 'MyTests' started"))
                checker.check(.contains("Test Suite 'MyTests' passed"))
                checker.check(.contains("Executed 2 tests, with 0 failures"))
            }
        }
    }
  
    func testSwiftTestWithResources() throws {
        try withTemporaryDirectory { dir in
            let toolDir = dir.appending(component: "swiftTestResources")
            try localFileSystem.createDirectory(toolDir)
            try localFileSystem.writeFileContents(
              toolDir.appending(component: "Package.swift"),
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
            try localFileSystem.createDirectory(toolDir.appending(component: "Sources"))
            try localFileSystem.createDirectory(toolDir.appending(components: "Sources", "AwesomeResources"))
            try localFileSystem.writeFileContents(
              toolDir.appending(components: "Sources", "AwesomeResources", "AwesomeResource.swift"),
              bytes: ByteString(encodingAsUTF8: """
                    import Foundation

                    public struct AwesomeResource {
                      public init() {}
                      public let hello = try! String(contentsOf: Bundle.module.url(forResource: "hello", withExtension: "txt")!)
                    }

                    """)
            )

            try localFileSystem.writeFileContents(
              toolDir.appending(components: "Sources", "AwesomeResources", "hello.txt"),
              bytes: ByteString(encodingAsUTF8: "hello")
            )

            try localFileSystem.createDirectory(toolDir.appending(component: "Tests"))
            try localFileSystem.createDirectory(toolDir.appending(components: "Tests", "AwesomeResourcesTest"))

            try localFileSystem.writeFileContents(
              toolDir.appending(components: "Tests", "AwesomeResourcesTest", "world.txt"),
              bytes: ByteString(encodingAsUTF8: "world")
            )

            try localFileSystem.writeFileContents(
                toolDir.appending(components: "Tests", "AwesomeResourcesTest", "MyTests.swift"),
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
          
            let testOutput = try sh(swiftTest, "--package-path", toolDir, "--filter", "MyTests.*").stderr

//             Check the test log.
              XCTAssertContents(testOutput) { checker in
                  checker.check(.contains("Test Suite 'MyTests' started"))
                  checker.check(.contains("Test Suite 'MyTests' passed"))
                  checker.check(.contains("Executed 2 tests, with 0 failures"))
              }
        }
    }
}
