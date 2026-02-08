//
//  CGenPluginsBuildPlanTests.swift
//  SwiftPM
//
//  Created by Doug Schaefer on 2026-02-06.
//

import Foundation
import Testing
import Basics
import PackageLoading
import _InternalBuildTestSupport
import Build

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph

@_spi(SwiftPMInternal)
@testable import PackageModel

@testable import SPMBuildCore

@Suite
struct CGenPluginsBuildPlanTests {
    enum Kind {
        case cModule
        case swiftModule
    }

    func setup(
        kind: Kind = .cModule,
        gened: [RelativePath],
        toolsVersion: ToolsVersion = .v6_3,
        observability: ObservabilityScope
    ) async throws -> BuildPlanResult {
        let sources = switch kind {
        case .cModule:
            [
                "/MyPkg/Sources/MyModule/MyModule.c",
                "/MyPkg/Sources/MyModule/include/MyModule.h",
            ]
        case .swiftModule:
            [
                "/MyPkg/Sources/MyModule/MyModule.swift",
            ]
        }

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPkg/Plugins/MyPlugin/MyPlugin.swift",
                "/MyPkg/Sources/MyGenerator/MyGenerator.swift",
                "/MyPkg/Sources/MyModule/data.in",
                "/MyPkg/Sources/MyCModule/include/MyCModule.h",
                "/MyPkg/Sources/MyCModule/MyCModule.c",
                "/MyPkg/Sources/MyExe/MyExe.swift"
            ] + sources
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createRootManifest(
                    displayName: "MyPkg",
                    path: "/MyPkg",
                    toolsVersion: toolsVersion,
                    products: [
                        .init(name: "MyExe", type: .executable, targets: ["MyExe"]),
                    ],
                    targets: [
                        .init(name: "MyGenerator", type: .executable),
                        .init(
                            name: "MyPlugin",
                            dependencies: ["MyGenerator"],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                        .init(name: "MyModule", dependencies: ["MyPlugin"]),
                        .init(name: "MyCModule", dependencies: ["MyModule"]),
                        .init(name: "MyExe", dependencies: ["MyCModule"], type: .executable)
                    ]
                )
            ],
            observabilityScope: observability
        )

        // TODO: this should be made a utility
        struct MockPluginScriptRunner: PluginScriptRunner {
            let genMessages: (
                _ sourceFiles: [Basics.AbsolutePath],
                _ workingDirectory: Basics.AbsolutePath,
            ) -> [PluginToHostMessage]

            func compilePluginScript(
                sourceFiles: [Basics.AbsolutePath],
                pluginName: String,
                toolsVersion: PackageModel.ToolsVersion,
                workers: UInt32,
                observabilityScope: Basics.ObservabilityScope,
                callbackQueue: DispatchQueue,
                delegate: any SPMBuildCore.PluginScriptCompilerDelegate,
                completion: @escaping (Result<SPMBuildCore.PluginCompilationResult, any Error>) -> Void)
            {
                callbackQueue.sync {
                    completion(.failure(StringError("unimplemented")))
                }
            }

            func runPluginScript(
                sourceFiles: [Basics.AbsolutePath],
                pluginName: String,
                initialMessage: Data,
                toolsVersion: PackageModel.ToolsVersion,
                workingDirectory: Basics.AbsolutePath,
                writableDirectories: [Basics.AbsolutePath],
                readOnlyDirectories: [Basics.AbsolutePath],
                allowNetworkConnections: [Basics.SandboxNetworkPermission],
                workers: UInt32,
                fileSystem: any Basics.FileSystem,
                observabilityScope: Basics.ObservabilityScope,
                callbackQueue: DispatchQueue,
                delegate: any SPMBuildCore.PluginScriptCompilerDelegate & SPMBuildCore.PluginScriptRunnerDelegate,
                completion: @escaping (Result<Int32, any Error>) -> Void)
            {
                callbackQueue.sync {
                    do {
                        let decoder = JSONDecoder.makeWithDefaults()
                        let encoder = JSONEncoder(outputFormatting: .prettyPrinted)

                        let initial = try decoder.decode(HostToPluginMessage.self, from: initialMessage)
                        guard case let .createBuildToolCommands(context: context, rootPackageId: _, targetId: _, pluginGeneratedSources: _, pluginGeneratedResources: _) = initial else {
                            completion(.failure(StringError("Invalid initial message")))
                            return
                        }
                        let workDir = try context.url(for: context.pluginWorkDirId)

                        for message in genMessages(sourceFiles, workDir) {
                            let data = try encoder.encode(message)
                            try delegate.handleMessage(data: data, responder: { _ in })
                        }
                        completion(.success(0))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }

            var hostTriple: Triple {
                get throws {
                    return try UserToolchain.default.targetTriple
                }
            }
        }

        let pluginScriptRunner = MockPluginScriptRunner { sourceFiles, outputDirectory in
            let inFiles = sourceFiles.filter({ $0.extension == "in" }).map(\.asURL)
            let outFiles = gened.map({ outputDirectory.appending($0).asURL })

            return [
                .defineBuildCommand(
                    configuration: .init(
                        executable: URL(filePath: "/foo"),
                        arguments: [],
                        environment: [:]
                    ),
                    inputFiles: inFiles,
                    outputFiles: outFiles
                )
            ]
        }

        let pluginConfiguration = PluginConfiguration(
            scriptRunner: pluginScriptRunner,
            workDirectory: "/PluginOut",
            disableSandbox: true
        )

        let pluginTools: [ResolvedModule.ID: [String: PluginTool]] = [
            .init(moduleName: "MyPlugin", packageIdentity: .plain("MyPkg")) : [
                "MyGenerator": .init(path: "/Foo", source: .built)
            ]
        ]

        return try await BuildPlanResult(
            plan: mockBuildPlan(
                triple: UserToolchain.default.targetTriple,
                graph: graph,
                pluginConfiguration: pluginConfiguration,
                pluginTools: pluginTools,
                fileSystem: fs,
                observabilityScope: observability
            )
        )
    }

    /// This is more to test out that the setup routines provide a good test environment
    @Test func testSwift() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        _ = try await setup(
            kind: .swiftModule,
            gened: ["Gened.swift"],
            observability: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics && !observability.hasWarningDiagnostics)
    }

    @Test func testSuccess() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let result = try await setup(
            gened: [
                "include/Gened.h",
                "include/module.modulemap",
                "include/Gened.apinotes",
                "Gened.c",
            ], observability: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics && !observability.hasWarningDiagnostics)

        let module = try #require(try result.allTargets(named: "MyModule").only?.clang())
        let pluginOutputDir: AbsolutePath = "/PluginOut/outputs/mypkg/MyModule/destination/MyPlugin"
        let pluginIncludeDir = pluginOutputDir.appending("include")
        #expect(module.pluginDerivedPublicHeaderPaths == [pluginIncludeDir])
        let pluginModuleMap = pluginIncludeDir.appending("module.modulemap")
        let pluginModuleMapFile = "-fmodule-map-file=\(pluginModuleMap.pathString)"
        #expect(module.pluginDerivedModuleMap == pluginModuleMap)
        #expect(module.pluginDerivedAPINotes == [pluginIncludeDir.appending("Gened.apinotes")])
        let pluginSource = pluginOutputDir.appending("Gened.c")
        #expect(try module.compilePaths().contains(where: { $0.source == pluginSource }))
        let cmd = try module.emitCommandLine(for: pluginSource)
        #expect(cmd.contains(pluginIncludeDir.pathString))

        // Ensure the C module consumes the generated module map
        let cModule = try #require(try result.allTargets(named: "MyCModule").only?.clang())
        let cModuleSource: AbsolutePath = "/MyPkg/Sources/MyCModule/MyCModule.c"
        #expect(try cModule.compilePaths().contains(where: { $0.source == cModuleSource }))
        let cModuleCmd = try cModule.emitCommandLine(for: cModuleSource)
        #expect(cModuleCmd.contains(pluginIncludeDir.pathString))
        #expect(cModuleCmd.contains(pluginModuleMapFile))

        // Ensure the Swift module does also
        let swiftModule = try #require(try result.allTargets(named: "MyExe").only?.swift())
        let swiftModuleArgs = try swiftModule.compileArguments()
        #expect(swiftModuleArgs.contains(pluginIncludeDir.pathString))
        #expect(swiftModuleArgs.contains(pluginModuleMapFile))
    }

    /// Test that generating C into Swift modules throws warnings
    @Test func testCinSwift() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        _ = try await setup(
            kind: .swiftModule,
            gened: [
                "include/Gened.h",
                "include/module.modulemap",
                "include/Gened.apinotes",
                "Gened.c",
            ], observability: observability.topScope
        )

        let warnings = observability.warnings.map(\.message)
        let messages: [String] = [
            "Only C modules support plugin generated C header files: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/include/Gened.h",
            "Only C modules support plugin generated module map files: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/include/module.modulemap",
            "Only C modules support plugin generated API notes files: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/include/Gened.apinotes",
            "Only C modules support plugin generated C source files: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/Gened.c",
        ]

        #expect(warnings.count == messages.count)
        for message in messages {
            #expect(warnings.contains(message))
        }

    }

    /// Test that the feature is disabled on previous tools versions
    @Test func testOldToolsVersion() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        _ = try await setup(
            gened: [
                "include/Gened.h",
                "include/module.modulemap",
                "include/Gened.apinotes",
                "Gened.c",
            ],
            toolsVersion: .v6_2,
            observability: observability.topScope
        )
        let warnings = observability.warnings.map(\.message)
        let messages: [String] = [
            "C header file generation requires tools version >= 6.3: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/include/Gened.h",
            "Module map generation requires tools version >= 6.3: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/include/module.modulemap",
            "API notes generation requires tools version >= 6.3: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/include/Gened.apinotes",
            "C source file generation requires tools version >= 6.3: /PluginOut/outputs/mypkg/MyModule/destination/MyPlugin/Gened.c",
        ]

        #expect(warnings.count == messages.count)
        for message in messages {
            #expect(warnings.contains(message))
        }
    }
}

extension HostToPluginMessage.InputContext {
    func url(for id: WireInput.URL.Id) throws -> AbsolutePath {
        // Compose a path based on an optional base path and a subpath.
        let wirePath = paths[id]
        let basePath = try paths[id].baseURLId.map{ try self.url(for: $0) }
        let path: AbsolutePath
        if let basePath {
            path = basePath.appending(wirePath.subpath)
        } else {
            path = AbsolutePath.root.appending(wirePath.subpath)
        }
        return path
    }
}
