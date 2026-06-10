//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import _IntegrationTestSupport
import _InternalTestSupport
import Testing
import struct TSCBasic.ByteString
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import Basics
@Suite(
    .tags(Tag.TestSize.large)
)
private struct BasicTests {

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8409", relationship: .defect),
        .requireUnrestrictedNetworkAccess("Test requires access to https://github.com"),
        .tags(
            Tag.UserWorkflow,
            Tag.Feature.Command.Build,
        ),
    )
    func testExamplePackageDealer() async throws {
        try await withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "dealer")
            let repoToClone = "https://github.com/swiftlang/example-package-dealer"
            withKnownIssue(isIntermittent: true) {
                // marking as withKnownIssue(intermittent: true) as git operation can fail.

                #if os(macOS)
                    // On macOS, we add the HOME variable to avoid git errors.
                    try sh("git\(ProcessInfo.exeSuffix)", "clone", repoToClone, packagePath, env: ["HOME": tempDir.pathString])
                #else
                    try sh("git\(ProcessInfo.exeSuffix)", "clone", repoToClone, packagePath)
                #endif
            }

            // Do not run the test when the git clone operation failed
            if !FileManager.default.fileExists(atPath: packagePath.pathString) {
                //TODO: use Test Cancellation when available
                //https://forums.swift.org/t/pitch-test-cancellation/81847/18
                #if compiler(>=6.3)
                    Issue.record("Can't clone the repository \(repoToClone), abording the test.", severity: .warning)
                #endif
                return
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
            let gitOutput = try sh("git\(ProcessInfo.exeSuffix)", "-C", packagePath, "status").stdout
            #expect(gitOutput.contains("nothing to commit, working tree clean"))

            // Verify that another 'swift build' does nothing.
            let build2Output = try await executeSwiftBuild(
                packagePath,
                buildSystem: .native,
            ).stdout
            #expect(build2Output.contains("Build complete"))

            // Check that no compilation happened (except for plugins which are allowed)
            // catch "Compiling xxx" but ignore "Compiling plugin" messages
            let compilingRegex = try Regex("Compiling (?!plugin)")
            #expect(build2Output.contains(compilingRegex) == false)
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
            .Feature.CommandLineArguments.VeryVerbose,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftPackageInitLibraryTests(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
                try await executeSwiftPackage(
                    packagePath,
                    configuration: config,
                    extraArgs: ["init", "--type", "library", "--enable-xctest", "--enable-swift-testing"],
                    buildSystem: buildSystem,
                )
                let packageOutput = try await executeSwiftTest(
                    packagePath,
                    configuration: config,
                    extraArgs: ["--vv"],
                    buildSystem: buildSystem,
                )

                // Check the test log.
                #expect(packageOutput.stdout.contains("Executed 1 test"), "stdout: '\(packageOutput.stdout)'\n\n\n stderr:'\(packageOutput.stderr)'")
                #expect(packageOutput.stdout.contains("Test run with 1 test"), "stdout: '\(packageOutput.stdout)'\n\n\n stderr:'\(packageOutput.stderr)'")

                // Check there were no compile errors or warnings.
                #expect(!packageOutput.stdout.contains("error"))
                #expect(!packageOutput.stdout.contains("warning"))
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Init,
            Tag.Feature.Command.Build,
            Tag.Feature.PackageType.Library,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftPackageInitLib(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let config = BuildConfiguration.debug
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                configuration: config,
                extraArgs: ["init", "--type", "library"],
                buildSystem: buildSystem,
            )
            let buildOutput = try await executeSwiftBuild(
                packagePath,
                configuration: config,
                buildSystem: buildSystem,
            ).stdout

            // Check the build log.
            switch buildSystem {
                case .native:
                    #expect(try #/Compiling .*Project.*/#.firstMatch(in: buildOutput) != nil)
                case .swiftbuild, .xcode:
                    break
            }
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftPackageLibsTests(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let config = BuildConfiguration.debug
        try withTemporaryDirectory { tempDir in
            // Create a new package with an executable target.
            let packagePath = tempDir.appending(component: "Project")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                configuration: config,
                extraArgs: ["init", "--type", "library"],
                buildSystem: buildSystem,
            )
            let output = try await executeSwiftTest(
                packagePath,
                configuration: config,
                buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftPackageWithSpaces(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
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
                configuration: config,
                extraArgs: ["-v"],
                buildSystem: buildSystem,
            ).stdout
            switch (buildSystem, config) {
                case (.native, .debug) :
                    let expression = ProcessInfo
                        .hostOperatingSystem != .windows ?
                        #/swiftc.* -module-name special_tool .* '@.*/more spaces/special tool/.build/[^/]+/debug/special_tool.build/sources'/# :
                        #/swiftc.* -module-name special_tool .* "@.*\\more spaces\\special tool\\.build\\[^\\]+\\debug\\special_tool.build\\sources"/#
                    #expect(try expression.firstMatch(in: buildOutput) != nil)
                case (.swiftbuild, _), (.xcode, _), (.native, .release):
                    break
            }
            #expect(buildOutput.contains("Build complete"))

            // Verify that the tool exists and works.
            let shOutput = try sh(
                try packagePath.appending(components: buildSystem.binPath(for: config) + ["special tool"])
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftRun(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let config = BuildConfiguration.debug
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "secho")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                configuration: config,
                extraArgs: ["init", "--type", "executable"],
                buildSystem: buildSystem,
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
                packagePath, "secho",
                configuration: config,
                extraArgs: [ "1", #""two""#],
                buildSystem: buildSystem,
            )

            // Check the run log.
            switch buildSystem {
                case .native:
                    let compilingRegex = try Regex("Compiling .*secho.*")
                    let linkingRegex: Regex<AnyRegexOutput> = try Regex("Linking .*secho")
                    #expect(result.stdout.contains(compilingRegex), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
                    #expect(result.stdout.contains(linkingRegex),  "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
                case .swiftbuild, .xcode:
                break
            }
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftTest(
        buildSystem: BuildSystemProvider.Kind,
    ) throws {
        let config = BuildConfiguration.debug
        try withTemporaryDirectory { tempDir in
            let packagePath = tempDir.appending(component: "swiftTest")
            try localFileSystem.createDirectory(packagePath)
            try await executeSwiftPackage(
                packagePath,
                configuration: config,
                extraArgs: ["init", "--type", "library"],
                buildSystem: buildSystem,
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
                configuration: config,
                extraArgs: [
                    "--filter",
                    "MyTests.*",
                    "--skip",
                    "testBaz",
                    "--vv",
                ],
                buildSystem: buildSystem,
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
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func testSwiftTestWithResources(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        try await fixture(name: "Miscellaneous/PackageWithResource/") { packagePath in

            let result = try await executeSwiftTest(
                packagePath,
                configuration: config,
                extraArgs: ["--filter", "MyTests.*", "--vv"],
                buildSystem: buildSystem,
            )

            // Check the test log.
            withKnownIssue(isIntermittent: true) {
                #expect(result.stdout.contains("Test Suite 'MyTests' started"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
                #expect(result.stdout.contains("Test Suite 'MyTests' passed"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
                #expect(result.stdout.contains("Executed 2 tests, with 0 failures"), "stdout: '\(result.stdout)'\n stderr:'\(result.stderr)'")
            } when: {
                [.linux, .windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild // Because the build failed
            }
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
