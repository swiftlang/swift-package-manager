//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Commands
import PackageGraph
import PackageLoading
import PackageModel
import SourceControl
import SPMBuildCore
import _InternalTestSupport
import Workspace
import Testing

import class Basics.AsyncProcess

/// Asserts if a directory (recursively) contains a file.
private func assertDirectoryContainsFile(dir: AbsolutePath, filename: String, sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        for entry in try walk(dir) {
            if entry.basename == filename { return }
        }
    } catch {
        Issue.record(StringError("Failed with error \(error)"), sourceLocation: sourceLocation)
    }
    Issue.record(StringError("Directory \(dir) does not contain \(filename)"), sourceLocation: sourceLocation)
}

@Suite(.serialized)
struct CFamilyTargetTestCase {
    @Test(arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testCLibraryWithSpaces(buildSystem: BuildSystemProvider.Kind) async throws {
        try await withKnownIssue("https://github.com/swiftlang/swift-build/issues/333") {
            try await fixture(name: "CFamilyTargets/CLibraryWithSpaces") { fixturePath in
                try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
                if buildSystem == .native {
                    let debugPath = fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
                    assertDirectoryContainsFile(dir: debugPath, filename: "Bar.c.o")
                    assertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
                }
            }
        } when: {
            buildSystem == .swiftbuild
        }
    }

    @Test(arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testCUsingCAndSwiftDep(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "DependencyResolution/External/CUsingCDep") { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            try await executeSwiftBuild(packageRoot, buildSystem: buildSystem)
            if buildSystem == .native {
                let debugPath = fixturePath.appending(components: "Bar", ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
                assertDirectoryContainsFile(dir: debugPath, filename: "Sea.c.o")
                assertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
            }
            let path = try SwiftPM.packagePath(for: "Foo", packageRoot: packageRoot)
            #expect(try GitRepository(path: path).getTags() == ["1.2.3"])
        }
    }

    @Test(arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testModuleMapGenerationCases(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "CFamilyTargets/ModuleMapGenerationCases") { fixturePath in
            try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
            if buildSystem == .native {
                let debugPath = fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
                assertDirectoryContainsFile(dir: debugPath, filename: "Jaz.c.o")
                assertDirectoryContainsFile(dir: debugPath, filename: "main.swift.o")
                assertDirectoryContainsFile(dir: debugPath, filename: "FlatInclude.c.o")
                assertDirectoryContainsFile(dir: debugPath, filename: "UmbrellaHeader.c.o")
            }
        }
    }

    @Test(arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testNoIncludeDirCheck(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "CFamilyTargets/CLibraryNoIncludeDir") { fixturePath in
            var buildError: (any Error)? = nil
            do {
                try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
            } catch {
                buildError = error
            }
            guard let buildError else {
                Issue.record(StringError("This build should throw an error"))
                return
            }
            // The err.localizedDescription doesn't capture the detailed error string so interpolate
            let errStr = "\(buildError)"
            let missingIncludeDirStr = "\(ModuleError.invalidPublicHeadersDirectory("Cfactorial"))"
            #expect(errStr.contains(missingIncludeDirStr))
        }
    }

    @Test(arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testCanForwardExtraFlagsToClang(buildSystem: BuildSystemProvider.Kind) async throws {
        // Try building a fixture which needs extra flags to be able to build.
        try await fixture(name: "CFamilyTargets/CDynamicLookup") { fixturePath in
            try await executeSwiftBuild(fixturePath, Xld: ["-undefined", "dynamic_lookup"], buildSystem: buildSystem)
            let debugPath = fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug")
            if buildSystem == .native {
                assertDirectoryContainsFile(dir: debugPath, filename: "Foo.c.o")
            }
        }
    }

    @Test(.requireHostOS(.macOS), arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testObjectiveCPackageWithTestTarget(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "CFamilyTargets/ObjCmacOSPackage") { fixturePath in
            // Build the package.
            try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
            if buildSystem == .native {
                assertDirectoryContainsFile(dir: fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug"), filename: "HelloWorldExample.m.o")
            }
            // Run swift-test on package.
            try await executeSwiftTest(fixturePath, buildSystem: buildSystem)
        }
    }

    @Test(arguments: [BuildSystemProvider.Kind.native, .swiftbuild])
    func testCanBuildRelativeHeaderSearchPaths(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "CFamilyTargets/CLibraryParentSearchPath") { fixturePath in
            try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
            if buildSystem == .native {
                assertDirectoryContainsFile(dir: fixturePath.appending(components: ".build", try UserToolchain.default.targetTriple.platformBuildPathComponent, "debug"), filename: "HeaderInclude.swiftmodule")
            }
        }
    }
}
