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

import _InternalBuildTestSupport
import _InternalTestSupport
import Basics
@testable import Build
import Foundation
import PackageLoading
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph
@_spi(SwiftPMInternal)
@testable import PackageModel
@testable import SPMBuildCore
import Testing

struct PluginInvocationFailureTests {
    @Test(
        "Build-tool plugin runner failures retain diagnostic context",
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10042", relationship: .defect)
    )
    func runnerFailureDiagnostic() async throws {
        let fileSystem = InMemoryFileSystem(
            emptyFiles:
            "/Foo/Plugins/FooPlugin/plugin.swift",
            "/Foo/Sources/Foo/source.swift"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Foo",
                    path: "/Foo",
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            type: .regular,
                            pluginUsages: [.plugin(name: "FooPlugin", package: nil)]
                        ),
                        TargetDescription(
                            name: "FooPlugin",
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let target = try #require(graph.allModules.first(where: { $0.name == "Foo" }))
        let plugin = try #require(graph.allModules.first(where: { $0.name == "FooPlugin" }))
        let buildParameters = mockBuildParameters(
            destination: .host,
            environment: BuildEnvironment(platform: .macOS, configuration: .debug),
            buildSystem: .native
        )
        let configuration = PluginConfiguration(
            scriptRunner: FailingPluginScriptRunner(),
            workDirectory: "/Foo/.build/plugins",
            disableSandbox: false
        )

        let results = try await BuildPlan.invokeBuildToolPlugins(
            for: target,
            destination: .target,
            configuration: configuration,
            buildParameters: buildParameters,
            modulesGraph: graph,
            tools: [plugin.id: [:]],
            additionalFileRules: [],
            pkgConfigDirectories: [],
            fileSystem: fileSystem,
            observabilityScope: observability.topScope,
            surfaceDiagnostics: true
        )

        let result = try #require(results.first)
        #expect(result.succeeded == false)

        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message.contains(FailingPluginScriptRunner.executable.pathString))
        #expect(diagnostic.message.contains("uncaught signal: 9"))
        #expect(diagnostic.message.contains(FailingPluginScriptRunner.stderr))
        #expect(diagnostic.metadata?.underlyingError != nil)

        let surfacedDiagnostic = try #require(observability.diagnostics.first(where: { $0.severity == .error }))
        #expect(surfacedDiagnostic.message == diagnostic.message)
        #expect(surfacedDiagnostic.metadata?.moduleName == target.name)
        #expect(surfacedDiagnostic.metadata?.pluginName == plugin.name)
    }
}

private struct FailingPluginScriptRunner: PluginScriptRunner {
    static let executable = AbsolutePath("/Foo/.build/plugins/cache/FooPlugin")
    static let stderr = "loader failure"

    var hostTriple: Triple {
        get throws {
            try UserToolchain.default.targetTriple
        }
    }

    func compilePluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptCompilerDelegate,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        callbackQueue.async {
            completion(.failure(StringError("unexpected plugin compilation")))
        }
    }

    func buildCommandLine(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope?
    ) -> (commandLine: [String], execName: String, execFilePath: AbsolutePath, diagFilePath: AbsolutePath) {
        fatalError("unexpected plugin compilation")
    }

    func runPluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        initialMessage: Data,
        toolsVersion: ToolsVersion,
        workingDirectory: AbsolutePath,
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        allowNetworkConnections: [SandboxNetworkPermission],
        workers: UInt32,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptCompilerDelegate & PluginScriptRunnerDelegate
    ) async throws -> Int32 {
        throw DefaultPluginScriptRunnerError.invocationEndedBySignal(
            signal: 9,
            command: [Self.executable.pathString],
            output: Self.stderr
        )
    }
}
