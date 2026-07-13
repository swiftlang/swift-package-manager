//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
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

@Suite(
    .serializedIfOnWindows,
    .tags(
        .TestSize.large,
        .Feature.CTargets,
    ),
)
struct MixedLanguageTargetTests {
    private func testMixedLanguageFixture(
        _ fixtureName: String,
        buildExtraArgs: [String] = [],
    ) async throws {
        try await fixture(name: fixtureName) { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: buildExtraArgs,
                buildSystem: .swiftbuild,
            )
        }
    }

    /// A library target that mixes Swift and C sources.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedSwiftCLibrary() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedSwiftCLibrary")
    }

    /// A library target that mixes Swift and C sources but has no public headers directory.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedSwiftCLibraryWithNoHeaders() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedSwiftCLibraryNoHeaders")
    }

    /// A library target that mixes Swift and C++ sources.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedSwiftCxxLibrary() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedSwiftCxxLibrary")
    }

    /// An executable target that mixes Swift and C sources.
    @Test(
        .tags(.Feature.Command.Build),
    )
    func mixedSwiftCExecutable() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedSwiftCExecutable")
    }

    /// An executable target that mixes Swift and C++ sources.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedSwiftCxxExecutable() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedSwiftCxxExecutable")
    }

    /// A pure-Swift executable that consumes a mixed-language library, calling both its
    /// Swift API and its C API.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedLanguageClient() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedLanguageClient")
    }

    /// A pure-Swift executable that consumes a mixed-language library with a custom modulemap, calling both its
    /// Swift API and its C API.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedLibraryWithCustomModuleMap() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedLibraryCustomModuleMap")
    }

    /// A mixed-language library exercising bidirectional Swift/C++ interop.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedCxxImportsGeneratedSwiftHeader() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedCxxUsesSwiftHeader")
    }

    /// A test target that imports both the Swift and C API of a mixed-language library.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func testTargetImportingMixedLibrary() async throws {
        try await testMixedLanguageFixture(
            "CFamilyTargets/MixedLibraryTestTarget",
            buildExtraArgs: ["--build-tests"],
        )
    }

    /// A test target that `@testable`-imports both the Swift and C API of a mixed-language executable.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func testTargetImportingMixedExecutable() async throws {
        try await testMixedLanguageFixture(
            "CFamilyTargets/MixedExecutableTestTarget",
            buildExtraArgs: ["--build-tests"],
        )
    }

    /// A test target that itself mixes Swift and C sources.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedSourceTestTarget() async throws {
        try await testMixedLanguageFixture(
            "CFamilyTargets/MixedSourceTestTarget",
            buildExtraArgs: ["--build-tests"],
        )
    }

    /// A `.macro` target that mixes Swift and C sources.
    @Test(
        .tags(.Feature.Command.Build)
    )
    func mixedSourceMacro() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedSourceMacro")
    }

    @Test(.tags(.Feature.Command.Build))
    func nativeBuildSystemRejectsMixedSources() async throws {
        try await fixture(name: "CFamilyTargets/MixedSwiftCLibrary") { fixturePath in
            do {
                try await executeSwiftBuild(
                    fixturePath,
                    configuration: .debug,
                    buildSystem: .native,
                )
                Issue.record("expected the native build system to reject the mixed-language target")
            } catch {
                #expect(
                    "\(error)".contains(
                        "mixed language source files in Swift targets are not supported by the native build system"
                    )
                )
            }
        }
    }

    /// A Swift target that transitively uses another Swift target's generated Objective-C interface.
    @Test(.requireHostOS(.macOS), .tags(.Feature.Command.Build))
    func crossLanguageObjCTypeThroughObjCTarget() async throws {
        try await fixture(name: "CFamilyTargets/CrossLanguageObjCType") { fixturePath in
            let manifestPath = fixturePath.appending("Package.swift").pathString

            // Without `experimentalMultiLang`, TargetA does not impart its generated Objective-C
            // header module map to Swift dependents, so TargetC cannot resolve TargetA's type
            // through TargetB and the build fails.
            await #expect(throws: (any Error).self) {
                try await executeSwiftBuild(fixturePath, configuration: .debug, buildSystem: .swiftbuild)
            }

            // Enabling the experimental feature lets TargetC resolve TargetA's module, so it builds.
            let manifest = try String(contentsOfFile: manifestPath, encoding: .utf8)
            try manifest
                .replacingOccurrences(
                    of: "// swift-tools-version: 6.4",
                    with: "// swift-tools-version: 6.4;(experimentalMultiLang)"
                )
                .write(toFile: manifestPath, atomically: true, encoding: .utf8)

            try await executeSwiftBuild(fixturePath, configuration: .debug, buildSystem: .swiftbuild)
        }
    }

    /// A mixed source library whose Objective-C code imports the Swift-generated header
    @Test(
        .requireHostOS(.macOS),
        .tags(.Feature.Command.Build)
    )
    func mixedTargetObjCImportsGeneratedSwiftHeader() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/MixedObjCUsesSwiftHeader")
    }

    @Test(.requireHostOS(.macOS), .tags(.Feature.Command.Build))
    func objCImplementationInSwift() async throws {
        try await testMixedLanguageFixture("CFamilyTargets/ObjCImplementationInSwift")
    }
}
