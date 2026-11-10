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
    var pluginHeaderFile: Basics.AbsolutePath { pluginIncludeDir.appending("Gened.h")}
    var pluginSourceFile: Basics.AbsolutePath { pluginOutputDir.appending("Gened.c") }

    func setup(
        toolsVersion: ToolsVersion,
        fs: FileSystem,
        observabilityScope: ObservabilityScope
    ) async throws -> SwiftBuildSupport.PIF.TopLevelObject {
        let gened: [RelativePath] = [
            "include/Gened.h",
            "include/module.modulemap",
            "include/Gened.apinotes",
            "Gened.c",
        ]

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
                        .init(
                            name: "MyExe",
                            dependencies: ["MyModule"],
                            type: .executable
                        )
                    ]
                )
            ],
            observabilityScope: observabilityScope
        )

        let pluginScriptRunner = MockPluginScriptRunner { initial in
            guard case let .createBuildToolCommands(context: context, rootPackageId: _, targetId: targetId, pluginGeneratedSources: _, pluginGeneratedResources: _) = initial else {
                Issue.record("Wrong initial command")
                return []
            }

            let target = context.targets[targetId]
            let inFiles: [URL]
            switch target.info {
            case .swiftSourceModuleInfo(moduleName: _, kind: _, sourceFiles: let sourceFiles, compilationConditions: _, linkedLibraries: _, linkedFrameworks: _):
                inFiles = sourceFiles.map({ context.path(for: $0) }).filter({ $0.extension == "in" }).map(\.asURL)
            case .clangSourceModuleInfo(moduleName: _, kind: _, sourceFiles: let sourceFiles, preprocessorDefinitions: _, headerSearchPaths: _, publicHeadersDirId: _, linkedLibraries: _, linkedFrameworks: _):
                inFiles = sourceFiles.map({ context.path(for: $0) }).filter({ $0.extension == "in" }).map(\.asURL)
            default:
                Issue.record("Not a source module")
                return []
            }

            let outputDirectory = context.path(for: context.pluginWorkDirId)
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
                addLocalRpaths: .always,
                pluginScriptRunner: pluginScriptRunner
            ),
            fileSystem: fs,
            observabilityScope: observabilityScope
        )

        return try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(
                destination: .host,
                buildSystemKind: .swiftbuild,
            )
        ).0
    }

    func setupSwiftModule(
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) async throws -> SwiftBuildSupport.PIF.TopLevelObject {
        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPkg/Plugins/MyPlugin/MyPlugin.swift",
                "/MyPkg/Sources/MyGenerator/MyGenerator.swift",
                "/MyPkg/Sources/MyModule/data.in",
                "/MyPkg/Sources/MyModule/MyModule.swift",
                "/MyPkg/Sources/MyExe/MyExe.swift"
            ]
        )

        return try await setup(toolsVersion: toolsVersion, fs: fs, observabilityScope: observabilityScope)
    }

    func setupClangModule(
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) async throws -> SwiftBuildSupport.PIF.TopLevelObject {
        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPkg/Plugins/MyPlugin/MyPlugin.swift",
                "/MyPkg/Sources/MyGenerator/MyGenerator.swift",
                "/MyPkg/Sources/MyModule/data.in",
                "/MyPkg/Sources/MyModule/include/MyModule.h",
                "/MyPkg/Sources/MyModule/MyModule.c",
                "/MyPkg/Sources/MyExe/MyExe.swift"
            ]
        )

        return try await setup(toolsVersion: toolsVersion, fs: fs, observabilityScope: observabilityScope)
    }

    @Test func testSwiftModule() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let pif = try await setupSwiftModule(toolsVersion: .vNext, observabilityScope: observability.topScope)

        #expect(!observability.hasErrorDiagnostics && !observability.hasWarningDiagnostics)

        let project = try #require(pif.workspace.projects.filter({ $0.underlying.name == "MyPkg" }).only)
        let modules = project.underlying.targets.filter({ $0.common.name == "MyModule" })
        for module in modules {
            for config in module.common.buildConfigs {
                let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
                #expect(impartedSwiftFlags.contains(pluginModuleMapArg))

                let swiftFlags = try #require(config.settings[.OTHER_SWIFT_FLAGS])
                #expect(swiftFlags.contains(pluginModuleMapArg))
                #expect(swiftFlags.contains("-import-underlying-module"))

                let moduleMapPath = try #require(config.settings[.MODULEMAP_PATH])
                #expect(moduleMapPath == pluginModuleMapFile.pathString)
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

    @Test func testSwiftModule64() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let toolsVersion: ToolsVersion = try #require(.init(string: "6.4", experimentalFeatures: [.experimentalCGen]))
        _ = try await setupSwiftModule(toolsVersion: toolsVersion, observabilityScope: observability.topScope)

        let warnings = observability.warnings.map(\.message)
        let messages: [String] = [
            "Only C modules support plugin generated C header files: \(pluginHeaderFile.pathString)",
            "Only C modules support plugin generated module map files: \(pluginModuleMapFile.pathString)",
            "Only C modules support plugin generated C source files: \(pluginSourceFile.pathString)",
        ]

        for message in messages {
            #expect(warnings.contains(message))
        }
    }

    @Test func testSwiftModuleUnsupported() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        _ = try await setupSwiftModule(toolsVersion: .v6_4, observabilityScope: observability.topScope)

        let warnings = observability.warnings.map(\.message)
        let messages: [String] = [
            "C header file generation not enabled: \(pluginHeaderFile.pathString)",
            "Module map generation not enabled: \(pluginModuleMapFile.pathString)",
            "C source file generation not enabled: \(pluginSourceFile.pathString)",
        ]

        for message in messages {
            #expect(warnings.contains(message))
        }
    }

    @Test func testCModule() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let pif = try await setupClangModule(toolsVersion: .vNext, observabilityScope: observability.topScope)

        #expect(!observability.hasErrorDiagnostics && !observability.hasWarningDiagnostics)

        let project = try #require(pif.workspace.projects.filter({ $0.underlying.name == "MyPkg" }).only)
        let modules = project.underlying.targets.filter({ $0.common.name == "MyModule" })
        for module in modules {
            for config in module.common.buildConfigs {
                let impartedCFlags = try #require(config.impartedBuildProperties.settings[.OTHER_CFLAGS])
                #expect(impartedCFlags.contains(pluginModuleMapArg))

                let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
                #expect(impartedSwiftFlags.contains(pluginModuleMapArg))

                let moduleMapPath = try #require(config.settings[.MODULEMAP_PATH])
                #expect(moduleMapPath == pluginModuleMapFile.pathString)
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

    @Test func testCModule64() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let toolsVersion: ToolsVersion = try #require(.init(string: "6.4", experimentalFeatures: [.experimentalCGen]))
        let pif = try await setupClangModule(toolsVersion: toolsVersion, observabilityScope: observability.topScope)

        #expect(!observability.hasErrorDiagnostics && !observability.hasWarningDiagnostics)

        let project = try #require(pif.workspace.projects.filter({ $0.underlying.name == "MyPkg" }).only)
        let modules = project.underlying.targets.filter({ $0.common.name == "MyModule" })
        for module in modules {
            for config in module.common.buildConfigs {
                let impartedCFlags = try #require(config.impartedBuildProperties.settings[.OTHER_CFLAGS])
                #expect(impartedCFlags.contains(pluginModuleMapArg))

                let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
                #expect(impartedSwiftFlags.contains(pluginModuleMapArg))

                let moduleMapPath = try #require(config.settings[.MODULEMAP_PATH])
                #expect(moduleMapPath == pluginModuleMapFile.pathString)
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

    @Test func testCModuleUnsupported() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        _ = try await setupClangModule(toolsVersion: .v6_4, observabilityScope: observability.topScope)

        let warnings = observability.warnings.map(\.message)
        let messages: [String] = [
            "C header file generation not enabled: \(pluginHeaderFile.pathString)",
            "Module map generation not enabled: \(pluginModuleMapFile.pathString)",
            "C source file generation not enabled: \(pluginSourceFile.pathString)",
        ]

        for message in messages {
            #expect(warnings.contains(message))
        }
    }
}
