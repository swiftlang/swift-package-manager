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
import PackageModel
import Testing
import _InternalTestSupport

@testable import SPMBuildCore

@Suite(
    .serialized,
    .tags(
        .TestSize.large,
    ),
)
struct PluginsBuildPlanTests {
    @Test(
        .tags(
            .Feature.Command.Build,
            .Feature.Plugin,
            .Feature.SourceGeneration,
        ),
        arguments: BuildConfiguration.allCases,
    )
    func buildToolsDatabasePath(
        config: BuildConfiguration,
    ) async throws {
        try await fixture(name: "Miscellaneous/Plugins/MySourceGenPlugin") { fixturePath in
            let (stdout, _) = try await executeSwiftBuild(
                fixturePath,
                configuration: config,
                buildSystem: .native
            )
            #expect(stdout.contains("Build complete!"))
            // FIXME: This is temporary until build of plugin tools is extracted into its own command.
            #expect(localFileSystem.exists(fixturePath.appending(RelativePath(".build/plugin-tools.db"))))
            #expect(localFileSystem.exists(fixturePath.appending(RelativePath(".build/build.db"))))
        }
    }

    @Test(
        .serialized,
        .tags(
            .Feature.Command.Package.CommandPlugin,
        ),
        .requireHostOS(.macOS),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func commandPluginDependenciesWhenNotCrossCompiling(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        let hostToolchain = try UserToolchain(
            swiftSDK: .hostSwiftSDK(environment: [:]),
            environment: [:]
        )
        let hostTriple = try! hostToolchain.targetTriple.withoutVersion().tripleString

        // By default, plugin dependencies are built for the host platform
        try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
            let hostBinPath = try await getBinPath(
                fixturePath,
                configuration: config,
                extraArgs: ["--triple", hostTriple],
                buildSystem: buildSystem,
            )
            let hostDebugBinPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--triple", hostTriple],
                buildSystem: buildSystem,
            )
            let (stdout, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: config,
                extraArgs: ["-v", "build-plugin-dependency"],
                buildSystem: buildSystem,
            )
            #expect(stdout.contains("Hello from dependencies-stub"))
            if buildSystem == .native {
                #expect(stderr.contains("Build of product 'plugintool' complete!"))
            }
            let pluginToolName: String
            switch buildSystem {
                case .native:
                pluginToolName = "plugintool-tool"
                case .swiftbuild:
                pluginToolName = "plugintool"
                case .xcode:
                pluginToolName = ""
                Issue.record("Test has not been updated for this build system")
            }
            expectFileExists(at: hostBinPath.appending(pluginToolName))
            expectFileExists(at: hostDebugBinPath.appending("placeholder"))
        }
    }

    @Test(
        .serialized,
        .tags(
            .Feature.Command.Package.CommandPlugin,
        ),
        .requireHostOS(.macOS),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func commandPluginDependenciesWhenCrossCompiling(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        let config = BuildConfiguration.debug
        let hostToolchain = try UserToolchain(
            swiftSDK: .hostSwiftSDK(environment: [:]),
            environment: [:]
        )
        // let hostTriple = try! hostToolchain.targetTriple.withoutVersion().tripleString

        let x86Triple = "x86_64-apple-macosx"
        let armTriple = "arm64-apple-macosx"
        let targetTriple = hostToolchain.targetTriple.arch == .aarch64 ? x86Triple : armTriple

        // When cross compiling the final product, plugin dependencies should still be built for the host
        try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
            let targetDebugBinPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--triple", targetTriple],
                buildSystem: buildSystem,
            )
            let hostBinPath = try await getBinPath(
                fixturePath,
                configuration: config,
                buildSystem: buildSystem,
            )
            let targetBinPath = try await getBinPath(
                fixturePath,
                configuration: config,
                extraArgs: ["--triple", targetTriple],
                buildSystem: buildSystem,
            )
            let (stdout, stderr) = try await executeSwiftPackage(
                fixturePath,
                configuration: config,
                extraArgs: ["-v", "--triple", targetTriple, "build-plugin-dependency"],
                buildSystem: buildSystem,
            )
            #expect(stdout.contains("Hello from dependencies-stub"))
            if buildSystem == .native {
                #expect(stderr.contains("Build of product 'plugintool' complete!"))
            }
            let pluginToolName: String
            let pluginToolBinPath: AbsolutePath
            switch buildSystem {
                case .native:
                pluginToolName = "plugintool-tool"
                pluginToolBinPath = hostBinPath
                case .swiftbuild:
                pluginToolName = "plugintool"
                pluginToolBinPath = targetBinPath
                case .xcode:
                pluginToolName = ""
                pluginToolBinPath = AbsolutePath("/")
                Issue.record("Test has not been updated for this build system")
            }

            expectFileExists(at: targetDebugBinPath.appending("placeholder"))
            expectFileExists(at: pluginToolBinPath.appending(pluginToolName))
        }
    }
    @Test(
        .tags(
            .Feature.Command.Package.Plugin,
        ),
        .requireHostOS(.macOS),
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func docCPluginForBinaryDependency(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Miscellaneous/Plugins/SymbolGraphForBinaryDependency") { fixturePath in
            let result = try await AsyncProcess.popen(arguments: [
                fixturePath.appending(RelativePath("FooKit/Scripts/archive_xcframework.sh")).pathString,
                "FooKit"
            ])
            try print(result.utf8Output())
            try print(result.utf8stderrOutput())
            #expect(result.exitStatus == .terminated(code: 0))
            // Before we add -F support for xcframework, this call will throw since the command will abort with a non-zero exit code
            await #expect(throws: Never.self) {
                _ = try await executeSwiftPackage(
                    fixturePath,
                    extraArgs: ["generate-symbol-graph"],
                    buildSystem: buildSystem
                )
            }
        }
    }
}
