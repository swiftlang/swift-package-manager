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
        .TestSize.large,
        .Feature.Command.Build,
        .Feature.SDK.StaticLinux,
    )
)
private struct StaticLinuxIntegrationTests {
    @Test(.requiresStaticLinuxSwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func basicSwiftExecutable(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "ValidLayouts/SingleModule/ExecutableNew") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndSDKIDForTesting(for: .staticLinux))

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

            let binary = try await getBinPath(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", "\(arch)-swift-linux-musl"],
                env: env,
                buildSystem: buildSystem,
            ).appending(component: "ExecutableNew")
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

    // Regression test for https://github.com/swiftlang/swift-package-manager/issues/10237:
    @Test(.requiresStaticLinuxSwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func cxxabiStaticLinking(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/SwiftExecWithCxxLibraries") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndSDKIDForTesting(for: .staticLinux))

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

            let binary = try await getBinPath(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", "\(arch)-swift-linux-musl"],
                env: env,
                buildSystem: buildSystem,
            ).appending(component: "tool")
            #expect(localFileSystem.exists(binary), "Expected binary at \(binary)")

            #if os(Linux)
            // Static-linux binaries are standalone ELFs that can run directly on a Linux host of the same arch.
            let result = try await AsyncProcess.popen(arguments: [binary.pathString])
            let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.exitStatus == .terminated(code: 0), "binary exited with non-zero status")
            #expect(stdout == "Hello from Static Linux! 3", "Unexpected output: \(stdout)")
            #endif
        }
    }

    // Verifies that `.when(platforms: [.linux])` conditions remain active when building with the
    // static Linux SDK.
    @Test(.requiresStaticLinuxSwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func linuxPlatformConditionRemainsActive(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/StaticLinuxPlatformCondition") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndSDKIDForTesting(for: .staticLinux))

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

            let binary = try await getBinPath(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--triple", "\(arch)-swift-linux-musl", "--target", "tool"],
                env: env,
                buildSystem: buildSystem,
            ).appending(component: "tool")
            #expect(localFileSystem.exists(binary), "Expected binary at \(binary)")

            #if os(Linux)
            // Static-linux binaries are standalone ELFs that can run directly on a Linux host of the same arch.
            let result = try await AsyncProcess.popen(arguments: [binary.pathString])
            let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.exitStatus == .terminated(code: 0), "binary exited with non-zero status")
            #expect(stdout == "Hello from Static Linux! 42", "Unexpected output: \(stdout)")
            #endif
        }
    }

    @Test(.requiresStaticLinuxSwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func flagOverridesToolset(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/FlagOverrides") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndSDKIDForTesting(for: .staticLinux))

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
            let triple = "\(arch)-swift-linux-musl"

            // Pass the `-DONE` flag to the Swift compiler via a toolset file instead of `-Xswiftc`.
            let toolsetPath = fixturePath.appending("toolset.json")
            try localFileSystem.writeFileContents(
                toolsetPath,
                string: """
                {
                  "schemaVersion": "1.0",
                  "swiftCompiler": { "extraCLIOptions": ["-DONE"] }
                }
                """
            )

            let extraArgs = ["--swift-sdk", sdkID, "--triple", triple, "--toolset", toolsetPath.pathString]

            let buildOutput = try await executeSwiftBuild(
                fixturePath,
                extraArgs: extraArgs,
                env: env,
                buildSystem: buildSystem,
            )
            #expect(buildOutput.stdout.contains("Build complete"))

            let binary = try await getBinPath(
                fixturePath,
                extraArgs: extraArgs,
                env: env,
                buildSystem: buildSystem,
            ).appending(component: "FlagOverrides")
            #expect(localFileSystem.exists(binary), "Expected binary at \(binary)")

            #if os(Linux)
            // Static-linux binaries are standalone ELFs that can run directly on a Linux host of the same arch.
            let result = try await AsyncProcess.popen(arguments: [binary.pathString])
            let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.exitStatus == .terminated(code: 0), "binary exited with non-zero status")
            let lines = stdout.split(separator: "\n").map(String.init)
            // The toolset flag applies to the target executable...
            #expect(lines.contains("Executable flag: ONE"))
            // ...but not to the host tool run by the build tool plugin.
            #expect(lines.contains("Plugin tool flag: NONE"))
            #endif
        }
    }
}
