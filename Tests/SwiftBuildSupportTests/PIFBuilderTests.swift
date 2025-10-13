//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Testing
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import SwiftBuild
import SwiftBuildSupport
import _InternalTestSupport
import Workspace

extension PIFBuilderParameters {
    fileprivate static func constructDefaultParametersForTesting(temporaryDirectory: Basics.AbsolutePath) throws -> Self {
        self.init(
            isPackageAccessModifierSupported: true,
            enableTestability: false,
            shouldCreateDylibForDynamicProducts: false,
            toolchainLibDir: temporaryDirectory.appending(component: "toolchain-lib-dir"),
            pkgConfigDirectories: [],
            supportedSwiftVersions: [.v4, .v4_2, .v5, .v6],
            pluginScriptRunner: DefaultPluginScriptRunner(
                fileSystem: localFileSystem,
                cacheDir: temporaryDirectory.appending(component: "plugin-cache-dir"),
                toolchain: try UserToolchain.default
            ),
            disableSandbox: false,
            pluginWorkingDirectory: temporaryDirectory.appending(component: "plugin-working-dir"),
            additionalFileRules: []
        )
    }
}

fileprivate func withGeneratedPIF(fromFixture fixtureName: String, do doIt: (SwiftBuildSupport.PIF.TopLevelObject, TestingObservability) async throws -> ()) async throws {
    try await fixture(name: fixtureName) { fixturePath in
        let observabilitySystem = ObservabilitySystem.makeForTesting()
        let workspace = try Workspace(
            fileSystem: localFileSystem,
            forRootPackage: fixturePath,
            customManifestLoader: ManifestLoader(toolchain: UserToolchain.default),
            delegate: MockWorkspaceDelegate()
        )
        let rootInput = PackageGraphRootInput(packages: [fixturePath], dependencies: [])
        let graph = try await workspace.loadPackageGraph(
            rootInput: rootInput,
            observabilityScope: observabilitySystem.topScope
        )
        let builder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(temporaryDirectory: fixturePath),
            fileSystem: localFileSystem,
            observabilityScope: observabilitySystem.topScope
        )
        let pif = try await builder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host)
        )
        try await doIt(pif, observabilitySystem)
    }
}

extension SwiftBuildSupport.PIF.Workspace {
    fileprivate func project(named name: String) throws -> SwiftBuildSupport.PIF.Project {
        let matchingProjects = projects.filter {
            $0.underlying.name == name
        }
        if matchingProjects.isEmpty {
            throw StringError("No project named \(name) in PIF workspace")
        } else if matchingProjects.count > 1 {
            throw StringError("Multiple projects named \(name) in PIF workspace")
        } else {
            return matchingProjects[0]
        }
    }
}

extension SwiftBuildSupport.PIF.Project {
    fileprivate func target(named name: String) throws -> ProjectModel.BaseTarget {
        let matchingTargets = underlying.targets.filter {
            $0.common.name == name
        }
        if matchingTargets.isEmpty {
            throw StringError("No target named \(name) in PIF project")
        } else if matchingTargets.count > 1 {
            throw StringError("Multiple target named \(name) in PIF project")
        } else {
            return matchingTargets[0]
        }
    }
}

extension SwiftBuild.ProjectModel.BaseTarget {
    fileprivate func buildConfig(named name: String) throws -> SwiftBuild.ProjectModel.BuildConfig {
        let matchingConfigs = common.buildConfigs.filter {
            $0.name == name
        }
        if matchingConfigs.isEmpty {
            throw StringError("No config named \(name) in PIF target")
        } else if matchingConfigs.count > 1 {
            throw StringError("Multiple configs named \(name) in PIF target")
        } else {
            return matchingConfigs[0]
        }
    }
}

@Suite
struct PIFBuilderTests {
    @Test func platformConditionBasics() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/UnknownPlatforms") { pif, observabilitySystem in
            // We should emit a warning to the PIF log about the unknown platform
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .warning && $0.message.contains("Ignoring settings assignments for unknown platform 'DoesNotExist'")
            }.count > 0)

            let releaseConfig = try pif.workspace
                .project(named: "UnknownPlatforms")
                .target(named: "UnknownPlatforms")
                .buildConfig(named: "Release")

            // The platforms with conditional settings should have those propagated to the PIF.
            #expect(releaseConfig.settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, .linux] == ["$(inherited)", "BAR"])
            #expect(releaseConfig.settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, .macOS] == ["$(inherited)", "BAZ"])
            #expect(releaseConfig.settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, .windows] == nil)
        }
    }

    @Test func pluginWithBinaryTargetDependency() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/Plugins/BinaryTargetExePlugin") { pif, observabilitySystem in
            // Verify that PIF generation succeeds for a package with a plugin that depends on a binary target
            #expect(pif.workspace.projects.count > 0)

            let project = try pif.workspace.project(named: "MyBinaryTargetExePlugin")

            // Verify the plugin target exists
            let pluginTarget = try project.target(named: "MyPlugin")
            #expect(pluginTarget.common.name == "MyPlugin")

            // Verify the executable target that uses the plugin exists
            let executableTarget = try project.target(named: "MyPluginExe")
            #expect(executableTarget.common.name == "MyPluginExe")

            // Verify no errors were emitted during PIF generation
            let errors = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            // Verify that the plugin target has a dependency (binary targets are handled differently in PIF)
            // The key test is that PIF generation succeeds without errors when a plugin depends on a binary target
            let binaryArtifactMessages = observabilitySystem.diagnostics.filter {
                $0.message.contains("found binary artifact")
            }
            #expect(binaryArtifactMessages.count > 0, "Expected to find binary artifact processing messages")
        }
    }
}
