//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
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
import _InternalTestSupport
import Workspace
import Testing

import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .serialized, // crash occurs when executed in parallel. needs investigation
    .tags(
        .FunctionalArea.ModuleMaps,
    ),
)
struct ModuleMapsTestCase {
    private func localFixture(
        name: String,
        cModuleName: String,
        rootpkg: String,
        buildSystem: BuildSystemProvider.Kind,
        config: BuildConfiguration,
        body: @escaping (AbsolutePath, [String]) async throws -> Void
    ) async throws {
        try await fixture(name: name) { fixturePath in
            let input = fixturePath.appending(components: cModuleName, "C", "foo.c")
            let outdir = try fixturePath.appending(components: [rootpkg] + buildSystem.binPath(for: config))
            try makeDirectories(outdir)
            let triple = try UserToolchain.default.targetTriple
            let output = outdir.appending("libfoo\(triple.dynamicLibraryExtension)")
            try await AsyncProcess.checkNonZeroExit(args: executableName("clang"), "-shared", input.pathString, "-o", output.pathString)

            var Xld = ["-L", outdir.pathString]
        #if os(Linux) || os(Android)
            Xld += ["-rpath", outdir.pathString]
        #endif

            try await body(fixturePath, Xld)
        }
    }

    @Test(
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func directDependency(
        buildData: BuildData,
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await withKnownIssue(isIntermittent: true) {
            try await localFixture(
                name: "ModuleMaps/Direct",
                cModuleName: "CFoo",
                rootpkg: "App",
                buildSystem: buildSystem,
                config: configuration,
            ) { fixturePath, Xld in
                try await executeSwiftBuild(
                    fixturePath.appending("App"),
                    configuration: configuration,
                    Xld: Xld,
                    buildSystem: buildSystem,
                )

                let executable = try fixturePath.appending(components: ["App"] + buildSystem.binPath(for: configuration) + ["App"])
                let releaseout = try await AsyncProcess.checkNonZeroExit(
                    args: executable.pathString
                )
                #expect(releaseout == "123\n")
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
            || (buildSystem == .swiftbuild && configuration == .release)
        }
    }

    @Test(
        .serialized, // crash occurs when executed in parallel. needs investigation
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func transitiveDependency(
        buildData: BuildData,
    ) async throws {
        let configuration = buildData.config
        let buildSystem = buildData.buildSystem
        try await withKnownIssue(isIntermittent: true) {
            try await localFixture(
                name: "ModuleMaps/Transitive",
                cModuleName: "packageD",
                rootpkg: "packageA",
                buildSystem: buildSystem,
                config: configuration,
            ) { fixturePath, Xld in
                try await executeSwiftBuild(
                    fixturePath.appending("packageA"),
                    configuration: configuration,
                    Xld: Xld,
                    buildSystem: buildSystem,
                )

                let executable = try fixturePath.appending(components: ["packageA"] + buildSystem.binPath(for: configuration) + ["packageA"])
                let out = try await AsyncProcess.checkNonZeroExit(
                    args: executable.pathString
                )
                #expect(out == """
                    calling Y.bar()
                    Y.bar() called
                    X.foo() called
                    123

                    """)
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
            || (buildSystem == .swiftbuild && configuration == .release)
        }
    }
}
