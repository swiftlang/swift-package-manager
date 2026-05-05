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

private func findWasmKit(sdkID: String) throws -> AbsolutePath? {
    let observability = ObservabilitySystem { _, _ in }
    let hostSDK = try SwiftSDK.hostSwiftSDK()
    let hostToolchain = try UserToolchain(swiftSDK: hostSDK)
    let hostToolchainBinDir = hostToolchain.swiftCompilerPath.parentDirectory

    let swiftSDKsDir = try localFileSystem.swiftSDKsDirectory
    guard localFileSystem.exists(swiftSDKsDir) else { return nil }

    let bundleStore = SwiftSDKBundleStore(
        swiftSDKsDirectory: swiftSDKsDir,
        hostToolchainBinDir: hostToolchainBinDir,
        fileSystem: localFileSystem,
        observabilityScope: observability.topScope,
        outputHandler: { _ in }
    )

    let hostTriple = try Triple.getVersionedHostTriple(
        usingSwiftCompiler: hostToolchain.swiftCompilerPath
    )
    let (_, swiftSDK) = try bundleStore.selectBundle(matching: sdkID, hostTriple: hostTriple)

    return swiftSDK.toolset.knownTools[.debugger]?.path
}

private func findCompilerAndWebAssemblySDKIDForTesting() async throws -> (AbsolutePath, String)? {
    try await findCompilerAndSDKIDForTesting { $0 == "wasm" }
}

extension Trait where Self == Testing.ConditionTrait {
    static var requiresWebAssemblySwiftSDK: Self {
        enabled("WebAssembly Swift SDK is not installed") {
            try await findCompilerAndWebAssemblySDKIDForTesting() != nil
        }
    }
}

@Suite(
    .serialized,
    .tags(
        Tag.Feature.Command.Build,
    )
)
private struct WebAssemblyIntegrationTests {
    @Test(.requiresWebAssemblySwiftSDK)
    func basicSwiftExecutable() async throws {
        try await fixture(name: "WebAssembly/SwiftExecutable") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndWebAssemblySDKIDForTesting())

            var env = Environment()
            env["SWIFT_EXEC"] = compilerPath.pathString

            let buildOutput = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID],
                env: env,
                buildSystem: .swiftbuild,
            )
            #expect(buildOutput.stdout.contains("Build complete"))

            let binPathOutput = try await executeSwiftBuild(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--show-bin-path"],
                env: env,
                buildSystem: .swiftbuild
            )
            let binPath = binPathOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let wasmBinary = try AbsolutePath(validating: binPath).appending(component: "WasmSwiftExe.wasm")
            #expect(localFileSystem.exists(wasmBinary), "Expected .wasm binary at \(wasmBinary)")

            let wasmkitPath = try #require(try findWasmKit(sdkID: sdkID), "wasmkit not found in Swift SDK \(sdkID)")
            let result = try await AsyncProcess.popen(
                arguments: [wasmkitPath.pathString, "run", wasmBinary.pathString]
            )
            let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.exitStatus == .terminated(code: 0), "wasmkit exited with non-zero status")
            #expect(stdout == "Hello from WebAssembly!", "Unexpected output: \(stdout)")
        }
    }

    @Test(.requiresWebAssemblySwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func flagOverrides(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/FlagOverrides") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndWebAssemblySDKIDForTesting())

            var env = Environment()
            env["SWIFT_EXEC"] = compilerPath.pathString

            let runOutput = try await executeSwiftRun(
                fixturePath,
                "FlagOverrides",
                extraArgs: ["--swift-sdk", sdkID],
                Xswiftc: ["-DONE"],
                env: env,
                buildSystem: buildSystem,
            )

            let lines = runOutput.stdout.split(separator: "\n").map(String.init)
            #expect(lines.contains("Executable flag: ONE"))
            #expect(lines.contains("Plugin tool flag: ONE"))
        }
    }

    @Test(.requiresWebAssemblySwiftSDK, arguments: SupportedBuildSystemOnAllPlatforms)
    func flagOverridesCommandPlugin(buildSystem: BuildSystemProvider.Kind) async throws {
        try await fixture(name: "Miscellaneous/FlagOverrides") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndWebAssemblySDKIDForTesting())

            var env = Environment()
            env["SWIFT_EXEC"] = compilerPath.pathString

            let pluginOutput = try await executeSwiftPackage(
                fixturePath,
                extraArgs: ["--swift-sdk", sdkID, "--allow-writing-to-package-directory", "build-and-run", "-DONE"],
                env: env,
                buildSystem: buildSystem,
            )

            let wasmBinary = try AbsolutePath(
                validating: pluginOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            #expect(localFileSystem.exists(wasmBinary), "Expected .wasm binary at \(wasmBinary)")

            let wasmkitPath = try #require(try findWasmKit(sdkID: sdkID), "wasmkit not found in Swift SDK \(sdkID)")
            let result = try await AsyncProcess.popen(
                arguments: [wasmkitPath.pathString, "run", wasmBinary.pathString]
            )
            let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.exitStatus == .terminated(code: 0), "wasmkit exited with non-zero status")
            let lines = stdout.split(separator: "\n").map(String.init)
            #expect(lines.contains("Executable flag: ONE"))
            #expect(lines.contains("Plugin tool flag: NONE"))
        }
    }

    @Test(.requiresWebAssemblySwiftSDK)
    func configuredSwiftSDKSearchPaths() async throws {
        try await fixture(name: "WebAssembly/ConfiguredSDKSearchPaths") { fixturePath in
            let (compilerPath, sdkID) = try #require(try await findCompilerAndWebAssemblySDKIDForTesting())

            var env = Environment()
            env["SWIFT_EXEC"] = compilerPath.pathString

            let externalDependencyPath = fixturePath.appending(component: "ExternalDependency")
            let consumerPath = fixturePath.appending(component: "Consumer")

            // Build a library we can use as mock "SDK content"
            _ = try await executeSwiftBuild(
                externalDependencyPath,
                extraArgs: ["--swift-sdk", sdkID],
                env: env,
                buildSystem: .swiftbuild,
            )
            let libBinPathOutput = try await executeSwiftBuild(
                externalDependencyPath,
                extraArgs: ["--swift-sdk", sdkID, "--show-bin-path"],
                env: env,
                buildSystem: .swiftbuild,
            )
            let libBinPath = try AbsolutePath(
                validating: libBinPathOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let staticArchive = libBinPath.appending(component: "libGreeter.a")
            let swiftModule = libBinPath.appending(component: "Greeter.swiftmodule")
            #expect(localFileSystem.exists(staticArchive), "Expected static archive at \(staticArchive)")
            #expect(localFileSystem.exists(swiftModule), "Expected Swift module at \(swiftModule)")
            let configuredSDKSearchPath = fixturePath.appending(component: "ConfiguredSDKSearchPath")
            try localFileSystem.createDirectory(configuredSDKSearchPath)
            try localFileSystem.copy(from: staticArchive, to: configuredSDKSearchPath.appending(component: "libGreeter.a"))
            try localFileSystem.copy(from: swiftModule, to: configuredSDKSearchPath.appending(component: "Greeter.swiftmodule"))

            // Configure the Swift SDK we're using with additional search paths for the mock SDK content.
            let triple = "wasm32-unknown-wasip1"
            try await SwiftPM.sdk.execute([
                "configure", sdkID, triple,
                "--include-search-path", configuredSDKSearchPath.pathString,
                "--library-search-path", configuredSDKSearchPath.pathString,
            ], env: env)
            defer {
                _ = try? await SwiftPM.sdk.execute([
                    "configure", sdkID, triple, "--reset",
                ], env: env)
            }

            // Build a second package which depends on the mock SDK content
            let buildOutput = try await executeSwiftBuild(
                consumerPath,
                extraArgs: ["--swift-sdk", sdkID],
                env: env,
                buildSystem: .swiftbuild,
            )
            #expect(buildOutput.stdout.contains("Build complete"))
            let consumerBinPathOutput = try await executeSwiftBuild(
                consumerPath,
                extraArgs: ["--swift-sdk", sdkID, "--show-bin-path"],
                env: env,
                buildSystem: .swiftbuild,
            )
            let consumerBinPath = try AbsolutePath(
                validating: consumerBinPathOutput.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let wasmBinary = consumerBinPath.appending(component: "GreeterUser.wasm")
            #expect(localFileSystem.exists(wasmBinary), "Expected .wasm binary at \(wasmBinary)")

            let wasmkitPath = try #require(try findWasmKit(sdkID: sdkID), "wasmkit not found in Swift SDK \(sdkID)")
            let result = try await AsyncProcess.popen(
                arguments: [wasmkitPath.pathString, "run", wasmBinary.pathString]
            )
            let stdout = try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.exitStatus == .terminated(code: 0), "wasmkit exited with non-zero status")
            #expect(stdout == "Hello from Greeter!", "Unexpected output: \(stdout)")
        }
    }
}
