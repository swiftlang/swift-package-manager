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
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import _InternalTestSupport
import Workspace
import Testing

import class Basics.AsyncProcess

/// Expects a directory (recursively) contains a file.
fileprivate func expectDirectoryContainsFile(
    dir: AbsolutePath,
    filename: String,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    do {
        for entry in try walk(dir) {
            if entry.basename == filename { return }
        }
    } catch {
        Issue.record("Failed with error \(error)", sourceLocation: sourceLocation)
    }
    Issue.record("Directory \(dir) does not contain \(filename)", sourceLocation: sourceLocation)
}

@Suite(
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.CTargets,
    ),
)
struct CFamilyTargetTestCase {
    @Test(
        .issue("https://github.com/swiftlang/swift-build/issues/333", relationship: .defect),
        .tags(
            .Feature.Command.Build,
            .Feature.SpecialCharacters,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func cLibraryWithSpaces(
        data: BuildData,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "CFamilyTargets/CLibraryWithSpaces") { fixturePath in
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                if data.buildSystem == .native {
                    let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
                    expectDirectoryContainsFile(dir: binPath, filename: "Bar.c.o")
                    expectDirectoryContainsFile(dir: binPath, filename: "Foo.c.o")
                }
            }
        } when: {
            data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .IssueWindowsPathLastConponent,
        .IssueWindowsRelativePathAssert,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func cUsingCAndSwiftDep(
        data: BuildData,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "DependencyResolution/External/CUsingCDep") { fixturePath in
                let packageRoot = fixturePath.appending("Bar")
                try await executeSwiftBuild(
                    packageRoot,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                if data.buildSystem == .native {
                    let binPath = try packageRoot.appending(components: data.buildSystem.binPath(for: data.config))
                    expectDirectoryContainsFile(dir: binPath, filename: "Sea.c.o")
                    expectDirectoryContainsFile(dir: binPath, filename: "Foo.c.o")
                }
                let path = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
                let actualTags = try GitRepository(path: path).getTags()
                #expect(actualTags == ["1.2.3"])
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .IssueWindowsPathLastConponent,
        .IssueWindowsRelativePathAssert,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func moduleMapGenerationCases(
        data: BuildData,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "CFamilyTargets/ModuleMapGenerationCases") { fixturePath in
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                if data.buildSystem == .native {
                    let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
                    expectDirectoryContainsFile(dir: binPath, filename: "Jaz.c.o")
                    expectDirectoryContainsFile(dir: binPath, filename: "main.swift.o")
                    expectDirectoryContainsFile(dir: binPath, filename: "FlatInclude.c.o")
                    expectDirectoryContainsFile(dir: binPath, filename: "UmbrellaHeader.c.o")
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func noIncludeDirCheck(
        data: BuildData,
    ) async throws {
        try await fixture(name: "CFamilyTargets/CLibraryNoIncludeDir") { fixturePath in
            let error = try await #require(throws: (any Error).self) {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
            }

            let errString = "\(error)"
            let missingIncludeDirStr = "\(ModuleError.invalidPublicHeadersDirectory("Cfactorial"))"
            #expect(errString.contains(missingIncludeDirStr))
        }
    }

    @Test(
        .IssueWindowsLongPath,
        .IssueWindowsPathLastConponent,
        .IssueWindowsRelativePathAssert,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.Command.Build,
            .Feature.CommandLineArguments.Xld,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func canForwardExtraFlagsToClang(
        data: BuildData,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "CFamilyTargets/CDynamicLookup") { fixturePath in
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    Xld: ["-undefined", "dynamic_lookup"],
                    buildSystem: data.buildSystem,
                )
                if data.buildSystem == .native {
                    let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
                    expectDirectoryContainsFile(dir: binPath, filename: "Foo.c.o")
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
        }
    }

    @Test(
        .requireHostOS(.macOS),
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Test,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func objectiveCPackageWithTestTarget(
        data: BuildData,
    ) async throws {
        try await fixture(name: "CFamilyTargets/ObjCmacOSPackage") { fixturePath in
            // Build the package.
            try await executeSwiftBuild(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )
            switch data.buildSystem {
            case .native:
                let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
                expectDirectoryContainsFile(dir: binPath, filename: "HelloWorldExample.m.o")
                expectDirectoryContainsFile(dir: binPath, filename: "HelloWorldExample.m.o")
            case .swiftbuild, .xcode:
                // there aren't any specific expectations to look for
                break
            }
            // Run swift-test on package.
            try await executeSwiftTest(
                fixturePath,
                configuration: data.config,
                buildSystem: data.buildSystem,
            )

        }
    }

    @Test(
        .IssueWindowsLongPath,
        .IssueWindowsPathLastConponent,
        .IssueWindowsRelativePathAssert,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            .Feature.Command.Build,
        ),
        buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.tags,
        arguments: buildDataUsingBuildSystemAvailableOnAllPlatformsWithTags.buildData,
    )
    func canBuildRelativeHeaderSearchPaths(
        data: BuildData,

    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "CFamilyTargets/CLibraryParentSearchPath") { fixturePath in
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: data.config,
                    buildSystem: data.buildSystem,
                )
                switch data.buildSystem {
                case .native:
                    let binPath = try fixturePath.appending(components: data.buildSystem.binPath(for: data.config))
                    expectDirectoryContainsFile(dir: binPath, filename: "HeaderInclude.swiftmodule")
                case .swiftbuild, .xcode:
                    // there aren't any specific expectations to look for
                    break
                }
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild
        }
    }
}
