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
        .IssueWindowsPathTestsFailures,  // Fails to build the project to due to incorrect Path handling
        arguments: BuildConfiguration.allCases,
    )
    func buildToolsDatabasePath(
        config: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
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
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
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

        let hostBinPathSegments = try buildSystem.binPath(
            for: config,
            triple: hostTriple,
        )
        let hostDebugBinPathSegments = try buildSystem.binPath(
            for: .debug,
            triple: hostTriple,
        )
        // By default, plugin dependencies are built for the host platform
        try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
            let hostBinPath: AbsolutePath = fixturePath.appending(components: hostBinPathSegments)
            let hostDebugBinPath: AbsolutePath = fixturePath.appending(components: hostDebugBinPathSegments)
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

        let hostBinPathSegments = try buildSystem.binPath(
            for: config,
        )
        let targetDebugBinPathSegments = try buildSystem.binPath(
            for: .debug,
            triple: targetTriple,
        )

        // When cross compiling the final product, plugin dependencies should still be built for the host
        try await fixture(name: "Miscellaneous/Plugins/CommandPluginTestStub") { fixturePath in
            // let hostBinPath: AbsolutePath = fixturePath.appending(components: hostBinPathSegments)
            let targetDebugBinPath: AbsolutePath = fixturePath.appending(components: targetDebugBinPathSegments)
            let hostBinPath = try fixturePath.appending(
                components: buildSystem.binPath(
                    for: config,
                )
            )
            let targetBinPath = try fixturePath.appending(
                components: buildSystem.binPath(
                    for: config,
                    triple: targetTriple,
                )
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

}
