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
import PackageModel
import SourceControl
import Workspace
import struct SPMBuildCore.BuildSystemProvider

import _InternalTestSupport
import Testing

struct ToolsVersionTests {

    @Test(
        .serialized,
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8416", relationship: .defect),
        .tags(
            .TestSize.large,
            .Feature.Command.Build,
            .Feature.Command.Package.ToolsVersion,
        ),
        // arguments: [BuildSystemProvider.Kind.swiftbuild], [BuildConfiguration.release],
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func toolsVersion(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await testWithTemporaryDirectory{ path in
            let fs = localFileSystem

            // Create a repo for the dependency to test against.
            let depPath = path.appending("Dep")
            try fs.createDirectory(depPath)
            initGitRepo(depPath)
            let repo = GitRepository(path: depPath)

            try fs.writeFileContents(
                depPath.appending("Package.swift"),
                string: """
                    // swift-tools-version:5.0
                    import PackageDescription
                    let package = Package(
                        name: "Dep",
                        products: [
                            .library(name: "Dep", targets: ["Dep"]),
                        ],
                        targets: [
                            .target(name: "Dep", path: "./")
                        ]
                    )
                    """
            )
            try fs.writeFileContents(
                depPath.appending("foo.swift"),
                string: #"public func foo() { print("foo@1.0") }"#
            )
            // v1.
            try repo.stageEverything()
            try repo.commit(message: "Initial")
            try repo.tag(name: "1.0.0")

            // v1.0.1
            _ = try await executeSwiftPackage(
                depPath,
                configuration: configuration,
                extraArgs: ["tools-version", "--set", "10000.1"],
                buildSystem: buildSystem,
            )
            try fs.writeFileContents(
                depPath.appending("foo.swift"),
                string: #"public func foo() { print("foo@1.0.1") }"#
            )
            try repo.stageEverything()
            try repo.commit(message: "1.0.1")
            try repo.tag(name: "1.0.1")

            // Create the primary repository.
            let primaryPath = path.appending("Primary")
            try fs.createDirectory(primaryPath, recursive: true)
            try fs.writeFileContents(
                primaryPath.appending("Package.swift"),
                string: """
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [.package(url: "../Dep", from: "1.0.0")],
                        targets: [.target(name: "Primary", dependencies: ["Dep"], path: ".")]
                    )
                    """
            )
            // Create a file.
            try fs.writeFileContents(
                primaryPath.appending("main.swift"),
                string: """
                    import Dep
                    Dep.foo()
                    """
            )
            _ = try await executeSwiftPackage(
                primaryPath,
                configuration: configuration,
                extraArgs: ["tools-version", "--set", "4.2"],
                buildSystem: buildSystem,
            ).stdout.spm_chomp()

            // Build the primary package.
            _ = try await executeSwiftBuild(
                primaryPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            let exe = primaryPath.appending(components: [".build", try UserToolchain.default.targetTriple.platformBuildPathComponent] + buildSystem.binPathSuffixes(for: configuration) + ["Primary"]).pathString
            // v1 should get selected because v1.0.1 depends on a (way) higher set of tools.
            try await withKnownIssue {
                let executableActualOutput = try await AsyncProcess.checkNonZeroExit(args: exe).spm_chomp()
                #expect(executableActualOutput == "foo@1.0")
            } when: {
                ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild
            }

            // Set the tools version to something high.
            _ = try await executeSwiftPackage(
                primaryPath,
                configuration: configuration,
                extraArgs: ["tools-version", "--set", "10000.1"],
                buildSystem: buildSystem,
            )

            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    primaryPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            ) { error in
                #expect(error.stderr.contains("is using Swift tools version 10000.1.0 but the installed version is \(ToolsVersion.current)"), "stderr: '\(error.stderr)'")
            }

            // Write the manifest with incompatible sources.
            try fs.writeFileContents(
                primaryPath.appending("Package.swift"),
                string: """
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [.package(url: "../Dep", from: "1.0.0")],
                        targets: [.target(name: "Primary", dependencies: ["Dep"], path: ".")],
                        swiftLanguageVersions: [.version("1000")])
                    """
            )
            _ = try await executeSwiftPackage(
                primaryPath,
                configuration: configuration,
                extraArgs: ["tools-version", "--set", "4.2"],
                buildSystem: buildSystem,
            ).stdout.spm_chomp()

            await expectThrowsCommandExecutionError(
                try await executeSwiftBuild(
                    primaryPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            ) { error in
                #expect(error.stderr.contains("package 'primary' requires minimum Swift language version 1000 which is not supported by the current tools version (\(ToolsVersion.current))"), "stderr: '\(error.stderr)'")
            }

            try fs.writeFileContents(
                primaryPath.appending("Package.swift"),
                string: """
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [.package(url: "../Dep", from: "1.0.0")],
                        targets: [.target(name: "Primary", dependencies: ["Dep"], path: ".")],
                        swiftLanguageVersions: [.version("\(ToolsVersion.current.major)"), .version("1000")])
                    """
             )
             _ = try await executeSwiftPackage(
                primaryPath,
                configuration: configuration,
                extraArgs: ["tools-version", "--set", "4.2"],
                buildSystem: buildSystem,
            ).stdout.spm_chomp()
             _ = try await executeSwiftBuild(
                primaryPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
    }
}
