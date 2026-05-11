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

import Basics
import Foundation
import PackageModel
import _InternalTestSupport
import SPMBuildCore
import Testing

import class Basics.AsyncProcess

@Suite(
    .tags(
        Tag.Feature.Command.Build,
    )
)
private struct StaticLinuxIntegrationTests {
    @Test(.requiresStaticLinuxSwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func basicSwiftExecutable(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndStaticLinuxSDKIDForTesting())

            var env = Environment()
            env["SWIFT_EXEC"] = compilerPath.pathString

            let arch: String
            #if os(Linux)
                #if arch(x86_64)
                    arch = "x86_64"
                #elseif arch(aarch64)
                    arch = "aarch64"
                #else
                    arch = "x86_64"
                #endif
            #else
                arch = "x86_64"
            #endif

            let buildOutput = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", "\(arch)-swift-linux-musl"],
                env: env,
                buildSystem: buildSystem,
            )
            #expect(buildOutput.stdout.contains("Build complete"))

            let binPathOutput = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", "\(arch)-swift-linux-musl", "--show-bin-path"],
                env: env,
                buildSystem: buildSystem,
            )
            let binPath = binPathOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let binary = try AbsolutePath(validating: binPath).appending(component: "ExecutableNew")
            #expect(localFileSystem.exists(binary), "Expected binary at \(binary)")

            #if os(Linux)
                // Static-linux binaries are standalone ELFs that can run directly on a Linux host of the same arch.
                let result = try await AsyncProcess.popen(arguments: [binary.pathString])
                let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(result.exitStatus == .terminated(code: 0), "binary exited with non-zero status")
                #expect(stdout == "Hello, world!", "Unexpected output: \(stdout)")
            #endif
        }
    }
}
