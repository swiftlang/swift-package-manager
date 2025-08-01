/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import _IntegrationTestSupport
import _InternalTestSupport
import Testing
import struct TSCBasic.ByteString
import Basics
@Suite(
    .tags(Tag.TestSize.large)
)
private struct BasicTests {

    @Test(
        .bug("https://github.com/swiftlang/swift-package-manager/issues/8409"),
        .requireUnrestrictedNetworkAccess("Test requires access to https://github.com"),
        .tags(
            Tag.UserWorkflow,
            Tag.Feature.Command.Build,
        ),
    )
    func testExamplePackageDealer() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "dealer")
            withKnownIssue(isIntermittent: true) {
                // marking as withKnownIssue(intermittent: trye) as git operation can fail.
                try sh("git\(ProcessInfo.exeSuffix)", "clone", "https://github.com/apple/example-package-dealer", packagePath)
            }
            let build1Output = try await executeSwiftBuild(
                packagePath,
                buildSystem: .native,
            ).stdout

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
            let build2Output = try await executeSwiftBuild(
                packagePath,
                buildSystem: .native,
            ).stdout
            #expect(build2Output.contains("Build complete"))
            #expect(build2Output.contains("Compiling") == false)
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
    )
    func testSwiftBuild() async throws {
        try await withTemporaryDirectory { tempDir in
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
            let buildOutput = try await executeSwiftBuild(
                packagePath,
                extraArgs: ["-v"],
                buildSystem: .native,
            ).stdout
            #expect(try #/swiftc.* -module-name tool/#.firstMatch(in: buildOutput) != nil)

            // Verify that the tool exists and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "tool"))
                .stdout
            #expect(toolOutput == "HI\(ProcessInfo.EOL)")
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.Command.Build,
            Tag.Feature.PackageType.Executable,
        ),
    )
    func testSwiftPackageInitExec() async throws {
        try await withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
            extraArgs: ["init", "--type", "executable"],
                buildSystem: .native,
            )
            let packageOutput = try await executeSwiftBuild(
                packagePath,
                buildSystem: .native,
            )

            // Check the build log.
            let compilingRegex = try Regex("Compiling .*Project.*")
            let linkingRegex = try Regex("Linking .*Project")
            #expect(packageOutput.stdout.contains(compilingRegex), "stdout: '\(packageOutput.stdout)'\n stderr:'\(packageOutput.stderr)'")
            #expect(packageOutput.stdout.contains(linkingRegex), "stdout: '\(packageOutput.stdout)'\n stderr:'\(packageOutput.stderr)'")
            #expect(packageOutput.stdout.contains("Build complete"), "stdout: '\(packageOutput.stdout)'\n stderr:'\(packageOutput.stderr)'")

            // Verify that the tool was built and works.
            let toolOutput = try sh(packagePath.appending(components: ".build", "debug", "Project"))
                .stdout
            #expect(toolOutput.lowercased().contains("hello, world!"))

            // Check there were no compile errors or warnings.
            #expect(packageOutput.stdout.contains("error") == false)
            #expect(packageOutput.stdout.contains("warning") == false)
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.Command.Test,
            Tag.Feature.PackageType.Executable,
        ),
    )
    func testSwiftPackageInitExecTests() async throws {
        try await withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            await withKnownIssue("error: no tests found; create a target in the 'Tests' directory") {
                try await executeSwiftPackage(
                    packagePath,
                    extraArgs: ["init", "--type", "executable"],
                    buildSystem: .native,
                )
                let packageOutput = try await executeSwiftTest(
                    packagePath,
                    extraArgs: ["--vv"],
                    buildSystem: .native,
                )

                // Check the test log.
                let compilingRegex = try Regex("Compiling .*ProjectTests.*")
                #expect(packageOutput.stdout.contains(compilingRegex), "stdout: '\(packageOutput.stdout)'\n stderr:'\(packageOutput.stderr)'")
                #expect(packageOutput.stdout.contains("Executed 1 test"), "stdout: '\(packageOutput.stdout)'\n stderr:'\(packageOutput.stderr)'")

                // Check there were no compile errors or warnings.
                #expect(packageOutput.stdout.contains("error") == false)
                #expect(packageOutput.stdout.contains("warning") == false)
            }
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.Command.Build,
            Tag.Feature.PackageType.Library,
        ),
    )
    func testSwiftPackageInitLib() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "library"],
                buildSystem: .native,
            )
            let buildOutput = try await executeSwiftBuild(
                packagePath,
                buildSystem: .native,
            ).stdout

            // Check the build log.
            #expect(try #/Compiling .*Project.*/#.firstMatch(in: buildOutput) != nil)
            #expect(buildOutput.contains("Build complete"))

            // Check there were no compile errors or warnings.
            #expect(buildOutput.contains("error") == false)
            #expect(buildOutput.contains("warning") == false)
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.Command.Test,
            Tag.Feature.PackageType.Library,
            Tag.Feature.SpecialCharacters,
        ),
    )
    func testSwiftPackageLibsTests() throws {
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "library"],
                buildSystem: .native,
            )
            let output = try await executeSwiftTest(
                packagePath,
                buildSystem: .native,
            )

            // Check there were no compile errors or warnings.
            #expect(output.stdout.contains("error") == false)
            #expect(output.stdout.contains("warning") == false)
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Build,
            Tag.Feature.SpecialCharacters,
        ),
    )
    func testSwiftPackageWithSpaces() async throws {
        try await withTemporaryDirectory { tempDir in
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
            let buildOutput = try await executeSwiftBuild(
                packagePath,
                extraArgs: ["-v"],
                buildSystem: .native,
            ).stdout
            let expression = ProcessInfo
                .hostOperatingSystem != .windows ?
                #/swiftc.* -module-name special_tool .* '@.*/more spaces/special tool/.build/[^/]+/debug/special_tool.build/sources'/# :
                #/swiftc.* -module-name special_tool .* "@.*\\more spaces\\special tool\\.build\\[^\\]+\\debug\\special_tool.build\\sources"/#
            #expect(try expression.firstMatch(in: buildOutput) != nil)
            #expect(buildOutput.contains("Build complete"))

            // Verify that the tool exists and works.
            let shOutput = try sh(
                packagePath.appending(components: ".build", "debug", "special tool")
            ).stdout

            #expect(shOutput == "HI\(ProcessInfo.EOL)")
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Run,
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.Executable,
        ),
    )
    func testSwiftRun() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "secho")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "executable"],
                buildSystem: .native,
            )
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
            let result = try await executeSwiftRun(
                packagePath, "secho", extraArgs: [ "1", #""two""#],
                buildSystem: .native,
            )

            // Check the run log.
            let compilingRegex = try Regex("Compiling .*secho.*")
            let linkingRegex = try Regex("Linking .*secho")
            #expect(result.stdout.contains(compilingRegex), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            #expect(result.stdout.contains(linkingRegex),  "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            #expect(result.stdout.contains("Build of product 'secho' complete"),  "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")

            #expect(result.stdout == "1 \"two\"\(ProcessInfo.EOL)")

        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Test,
            Tag.Feature.Command.Package.Init,
            Tag.Feature.PackageType.Library,
        ),
    )
    func testSwiftTest() throws {
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "swiftTest")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                extraArgs: ["init", "--type", "library"],
                buildSystem: .native,
            )
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
            let result = try await executeSwiftTest(
                packagePath,
                extraArgs: [
                    "--filter",
                    "MyTests.*",
                    "--skip",
                    "testBaz",
                    "--vv",
                ],
                buildSystem: .native,
            )

            // Check the test log.
            #expect(result.stdout.contains("Test Suite 'MyTests' started"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            #expect(result.stdout.contains("Test Suite 'MyTests' passed"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            #expect(result.stdout.contains("Executed 2 tests, with 0 failures"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Test,
            Tag.Feature.Resource,
        ),
    )
    func testSwiftTestWithResources() async throws {
        try await fixture(name: "Miscellaneous/PackageWithResource/") { packagePath in

            let result = try await executeSwiftTest(
                packagePath,
                extraArgs: ["--filter", "MyTests.*", "--vv"],
                buildSystem: .native,
            )

            // Check the test log.
            #expect(result.stdout.contains("Test Suite 'MyTests' started"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            #expect(result.stdout.contains("Test Suite 'MyTests' passed"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            #expect(result.stdout.contains("Executed 2 tests, with 0 failures"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
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
