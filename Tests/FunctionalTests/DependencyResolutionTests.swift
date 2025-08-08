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

import Basics
import Commands
import Foundation
import PackageModel
import SourceControl
import Testing
import Workspace
import _InternalTestSupport

import struct SPMBuildCore.BuildSystemProvider
import enum TSCUtility.Git

@Suite(
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.DependencyResolution,
    ),
)
struct DependencyResolutionTests {
    @Test(
        .IssueWindowsLongPath,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func internalSimple(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: (ProcessInfo.hostOperatingSystem == .windows)) {
            try await fixture(name: "DependencyResolution/Internal/Simple") { fixturePath in
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )

                let binPath = try fixturePath.appending(components: buildSystem.binPath(for: configuration))
                let executablePath = binPath.appending(components: "Foo")
                let output = try await AsyncProcess.checkNonZeroExit(args: executablePath.pathString).withSwiftLineEnding
                #expect(output == "Foo\nBar\n")
            }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8984", relationship: .defect),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func internalExecAsDep(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/Internal/InternalExecutableAsDependency") { fixturePath in
            await withKnownIssue {
                await #expect(throws: (any Error).self) {
                    try await executeSwiftBuild(
                        fixturePath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
            } when: {
                configuration == .release && buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem != .windows  // an error is not raised.
            }
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func internalComplex(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: ProcessInfo.hostOperatingSystem == .windows) {
            try await fixture(name: "DependencyResolution/Internal/Complex") { fixturePath in
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )

                let binPath = try fixturePath.appending(components: buildSystem.binPath(for: configuration))
                let executablePath = binPath.appending(components: "Foo")
                let output = try await AsyncProcess.checkNonZeroExit(args: executablePath.pathString)
                    .withSwiftLineEnding
                #expect(output == "meiow Baz\n")
            }
        } when: {
            (ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild)
        }
    }

    /// Check resolution of a trivial package with one dependency.
    @Test(
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func externalSimple(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "DependencyResolution/External/Simple") { fixturePath in
                // Add several other tags to check version selection.
                let repo = GitRepository(path: fixturePath.appending(components: "Foo"))
                for tag in ["1.1.0", "1.2.0"] {
                    try repo.tag(name: tag)
                }

                let packageRoot: AbsolutePath = fixturePath.appending("Bar")
                try await executeSwiftBuild(
                    packageRoot,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let binPath = try packageRoot.appending(components: buildSystem.binPath(for: configuration))
                let executablePath = binPath.appending(components: executableName("Bar"))
                #expect(
                    localFileSystem.exists(executablePath),
                    "Path \(executablePath) does not exist",
                )
                let path = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
                #expect(try GitRepository(path: path).getTags().contains("1.2.3"))
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .IssueLdFailsUnexpectedly,
        .issue("rdar://162339964", relationship: .defect),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func externalComplex(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(
            isIntermittent: ProcessInfo.hostOperatingSystem == .windows
                // rdar://162339964
                || (ProcessInfo.isHostAmazonLinux2() && buildSystem == .swiftbuild)
        ) {
            try await fixture(name: "DependencyResolution/External/Complex") { fixturePath in
                let packageRoot = fixturePath.appending("app")
                try await executeSwiftBuild(
                    packageRoot,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
                let binPath = try packageRoot.appending(components: buildSystem.binPath(for: configuration))
                let executablePath = binPath.appending(components: "Dealer")
                expectFileExists(at: executablePath)
                let output = try await AsyncProcess.checkNonZeroExit(args: executablePath.pathString)
                    .withSwiftLineEnding
                #expect(output == "♣︎K\n♣︎Q\n♣︎J\n♣︎10\n♣︎9\n♣︎8\n♣︎7\n♣︎6\n♣︎5\n♣︎4\n")
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows  // due to long path issues
                || (ProcessInfo.isHostAmazonLinux2() && buildSystem == .swiftbuild)  // Linker ld throws an unexpected error.
        }
    }

    @Test(
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func convenienceBranchInit(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "DependencyResolution/External/Branch") { fixturePath in
                // Tests the convenience init .package(url: , branch: )
                let app = fixturePath.appending("Bar")
                try await executeSwiftBuild(
                    app,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueProductTypeForObjectLibraries,
        .tags(
            Tag.Feature.Mirror,
            Tag.Feature.Command.Package.ShowDependencies,
            Tag.Feature.Command.Package.Config,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func mirrors(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue("https://github.com/swiftlang/swift-build/issues/609", isIntermittent: true) {
            try await fixture(name: "DependencyResolution/External/Mirror") { fixturePath in
                let prefix = try resolveSymlinks(fixturePath)
                let appPath = prefix.appending("App")
                let packageResolvedPath = appPath.appending("Package.resolved")

                // prepare the dependencies as git repos
                for directory in ["Foo", "Bar", "BarMirror"] {
                    let path = prefix.appending(component: directory)
                    _ = try await AsyncProcess.checkNonZeroExit(args: Git.tool, "-C", path.pathString, "init")
                    _ = try await AsyncProcess.checkNonZeroExit(
                        args: Git.tool,
                        "-C",
                        path.pathString,
                        "checkout",
                        "-b",
                        "newMain"
                    )
                }

                // run with no mirror
                do {
                    let output = try await executeSwiftPackage(
                        appPath,
                        configuration: configuration,
                        extraArgs: ["show-dependencies"],
                        buildSystem: buildSystem,
                    )
                    // logs are in stderr
                    #expect(output.stderr.contains("Fetching \(prefix.appending("Foo").pathString)\n"))
                    #expect(output.stderr.contains("Fetching \(prefix.appending("Bar").pathString)\n"))
                    // results are in stdout
                    #expect(output.stdout.contains("foo<\(prefix.appending("Foo").pathString)@unspecified"))
                    #expect(output.stdout.contains("bar<\(prefix.appending("Bar").pathString)@unspecified"))

                    let resolvedPackages: String = try localFileSystem.readFileContents(packageResolvedPath)
                    #expect(resolvedPackages.contains(prefix.appending("Foo").escapedPathString))
                    #expect(resolvedPackages.contains(prefix.appending("Bar").escapedPathString))

                    try await executeSwiftBuild(
                        appPath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }

                // clean
                try localFileSystem.removeFileTree(appPath.appending(".build"))
                try localFileSystem.removeFileTree(packageResolvedPath)

                // set mirror
                _ = try await executeSwiftPackage(
                    appPath,
                    configuration: configuration,
                    extraArgs: [
                        "config",
                        "set-mirror",
                        "--original-url",
                        prefix.appending("Bar").pathString,
                        "--mirror-url",
                        prefix.appending("BarMirror").pathString,
                    ],
                    buildSystem: buildSystem,
                )

                // run with mirror
                do {
                    let output = try await executeSwiftPackage(
                        appPath,
                        configuration: configuration,
                        extraArgs: ["show-dependencies"],
                        buildSystem: buildSystem,
                    )
                    // logs are in stderr
                    #expect(output.stderr.contains("Fetching \(prefix.appending("Foo").pathString)\n"))
                    #expect(output.stderr.contains("Fetching \(prefix.appending("BarMirror").pathString)\n"))
                    #expect(!output.stderr.contains("Fetching \(prefix.appending("Bar").pathString)\n"))
                    // result are in stdout
                    #expect(output.stdout.contains("foo<\(prefix.appending("Foo").pathString)@unspecified"))
                    #expect(
                        output.stdout.contains(
                            "barmirror<\(prefix.appending("BarMirror").pathString)@unspecified"
                        )
                    )
                    #expect(!output.stdout.contains("bar<\(prefix.appending("Bar").pathString)@unspecified"))

                    // rdar://52529014 mirrors should not be reflected in `Package.resolved` file
                    let resolvedPackages: String = try localFileSystem.readFileContents(packageResolvedPath)
                    #expect(resolvedPackages.contains(prefix.appending("Foo").escapedPathString))
                    #expect(resolvedPackages.contains(prefix.appending("Bar").escapedPathString))
                    #expect(!resolvedPackages.contains(prefix.appending("BarMirror").escapedPathString))

                    try await executeSwiftBuild(
                        appPath,
                        configuration: configuration,
                        buildSystem: buildSystem,
                    )
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            Tag.Feature.Command.Package.Update,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func packageLookupCaseInsensitive(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "DependencyResolution/External/PackageLookupCaseInsensitive") {
            fixturePath in
            try await executeSwiftPackage(
                fixturePath.appending("pkg"),
                configuration: configuration,
                extraArgs: ["update"],
                buildSystem: buildSystem,
            )
        }
    }
}
