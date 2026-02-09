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

import Foundation
import Basics
import PackageLoading
import SwiftBuildSupport
import Testing
import _InternalTestSupport
import SwiftBuild

@testable import SPMBuildCore

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) @testable import PackageGraph
@_spi(SwiftPMInternal) @testable import PackageModel

@Suite struct CGenPIFTests {
    enum Kind {
        case cModule
        case swiftModule
    }

    let pluginOutputDir: Basics.AbsolutePath = "/plugin-working-dir/outputs/mypkg/MyModule/tools/MyPlugin"
    var pluginIncludeDir: Basics.AbsolutePath { pluginOutputDir.appending("include") }
    var pluginModuleMapFile: Basics.AbsolutePath { pluginIncludeDir.appending("module.modulemap") }
    var pluginModuleMapArg: String { "-fmodule-map-file=\(pluginModuleMapFile.pathString)" }
    var pluginAPINotesFile: Basics.AbsolutePath { pluginIncludeDir.appending("Gened.apinotes")}
    var pluginHeaderFile: Basics.AbsolutePath { pluginIncludeDir.appending("Gened.h")}
    var pluginSourceFile: Basics.AbsolutePath { pluginOutputDir.appending("Gened.c") }

    func setup(
        kind: Kind = .cModule,
        gened: [RelativePath],
        toolsVersion: ToolsVersion = .v6_3,
        observability: ObservabilityScope
    ) async throws -> SwiftBuildSupport.PIF.TopLevelObject {
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

        let pifBuilder: PIFBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root,
                addLocalRpaths: true,
                pluginScriptRunner: pluginScriptRunner
            ),
            fileSystem: fs,
            observabilityScope: observability
        )

        return try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host)
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

    @Test func testSuccessPath() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let pif = try await setup(
            gened: [
                "include/Gened.h",
                "include/module.modulemap",
                "include/Gened.apinotes",
                "Gened.c",
            ], observability: observability.topScope
        )
        #expect(!observability.hasErrorDiagnostics && !observability.hasWarningDiagnostics)

        let project = try #require(pif.workspace.projects.filter({ $0.underlying.name == "MyPkg" }).only)
        let modules = project.underlying.targets.filter({ $0.common.name == "MyModule" })
        for module in modules {
            for config in module.common.buildConfigs {
                let headerSearchPaths = try #require(config.settings[.HEADER_SEARCH_PATHS])
                #expect(headerSearchPaths.contains(pluginIncludeDir.pathString))
                let impartedHeaderPaths = try #require(config.impartedBuildProperties.settings[.HEADER_SEARCH_PATHS])
                #expect(impartedHeaderPaths.contains(pluginIncludeDir.pathString))

                let impartedCFlags = try #require(config.impartedBuildProperties.settings[.OTHER_CFLAGS])
                #expect(impartedCFlags.contains(pluginModuleMapArg))
                let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
                #expect(impartedSwiftFlags.contains(pluginModuleMapArg))
            }

            // Make sure our generated source is included
            let sourcesPhase: ProjectModel.SourcesBuildPhase = try #require(module.common.buildPhases.compactMap({
                guard case let .sources(sourcesBuildPhase) = $0 else {
                    return nil
                }
                return sourcesBuildPhase
            }).only)
            let x = sourcesPhase.files.contains(where: {
                guard case .reference(id: let refId) = $0.ref,
                      let file = try? project.underlying.mainGroup.findSource(ref: refId)
                else {
                    return false
                }
                return file == pluginSourceFile
            })
            #expect(x)
        }
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
            "Only C modules support plugin generated C header files: \(pluginHeaderFile.pathString)",
            "Only C modules support plugin generated module map files: \(pluginModuleMapFile.pathString)",
            "Only C modules support plugin generated API notes files: \(pluginAPINotesFile.pathString)",
            "Only C modules support plugin generated C source files: \(pluginSourceFile.pathString)",
        ]

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
            "C header file generation requires tools version >= 6.3: \(pluginHeaderFile.pathString)",
            "Module map generation requires tools version >= 6.3: \(pluginModuleMapFile.pathString)",
            "API notes generation requires tools version >= 6.3: \(pluginAPINotesFile.pathString)",
            "C source file generation requires tools version >= 6.3: \(pluginSourceFile.pathString)",
        ]

        for message in messages {
            #expect(warnings.contains(message))
        }
    }
}

extension HostToPluginMessage.InputContext {
    func url(for id: WireInput.URL.Id) throws -> Basics.AbsolutePath {
        // Compose a path based on an optional base path and a subpath.
        let wirePath = paths[id]
        let basePath = try paths[id].baseURLId.map{ try self.url(for: $0) }
        let path: Basics.AbsolutePath
        if let basePath {
            path = basePath.appending(wirePath.subpath)
        } else {
            path = AbsolutePath.root.appending(wirePath.subpath)
        }
        return path
    }
}

extension ProjectModel.Group {
    func findSource(ref: GUID) throws -> Basics.AbsolutePath? {
        for child in subitems {
            switch child {
            case .file(let file):
                if file.id == ref {
                    if let file = try? Basics.AbsolutePath(validating: file.path) {
                        return file
                    }
                    guard self.pathBase == .absolute else {
                        return nil
                    }
                    let groupPath = try Basics.AbsolutePath(validating: self.path)
                    return groupPath.appending(file.path)
                }
            case .group(let group):
                if let file = try group.findSource(ref: ref) {
                    return file
                }
            }
        }
        return nil
    }
}
