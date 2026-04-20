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

package func swiftCompilerTag(compilerPath: AbsolutePath) async -> String? {
    guard let result = try? await AsyncProcess.popen(args: compilerPath.pathString, "-print-target-info") else {
        return nil
    }
    guard result.exitStatus == .terminated(code: 0) else {
        return nil
    }
    struct SwiftPrintTargetInfo: Decodable {
        var swiftCompilerTag: String
    }
    return try? JSONDecoder().decode(SwiftPrintTargetInfo.self, from: result.utf8Output()).swiftCompilerTag
}

package func findSwiftSDK(compilerPath: AbsolutePath, _ name: String) async -> String? {
    guard let compilerTag = await swiftCompilerTag(compilerPath: compilerPath) else {
        return nil
    }
    let prefix = "\(compilerTag)_"
    guard let result = try? await SwiftPM.sdk.execute(["list"]) else {
        return nil
    }
    let sdks = result.stdout.components(separatedBy: "\n")
        .map { $0.spm_chomp() }
        .filter { !$0.isEmpty }
    let matchingSDKs = sdks.filter { sdk in
        guard sdk.hasPrefix(prefix) else { return false }
        let suffix = String(sdk.dropFirst(prefix.count))
        return name == suffix
    }
    return matchingSDKs.count == 1 ? matchingSDKs[0] : nil
}

private func githubActionsToolchain() -> AbsolutePath? {
    let userToolchainsDir = AbsolutePath("/github/home/.swift-toolchains")
    let userToolchains = try? FileManager.default.contentsOfDirectory(atPath: userToolchainsDir.pathString)
    guard let userToolchains, userToolchains.count == 1 else {
        return nil
    }
    return userToolchainsDir.appending(component: userToolchains[0])
}

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

func findCompilerAndWebAssemblySDKIDForTesting() async throws -> (AbsolutePath, String)? {
    let compilerPath: AbsolutePath
    if let githubActionsToolchain = githubActionsToolchain() {
        compilerPath = githubActionsToolchain.appending(components: ["usr", "bin", "swiftc\(ProcessInfo.exeSuffix)"])
    } else {
        compilerPath = try UserToolchain(swiftSDK: SwiftSDK.hostSwiftSDK()).swiftCompilerPath
    }

    guard let sdkID = await findSwiftSDK(compilerPath: compilerPath, "wasm") else {
        return nil
    }

    return (compilerPath, sdkID)
}


extension Trait where Self == Testing.ConditionTrait {
    static var requiresWebAssemblySwiftSDK: Self {
        enabled("WebAssembly Swift SDK is not installed") {
            try await findCompilerAndWebAssemblySDKIDForTesting() != nil
        }
    }
}

@Suite(
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
}
