//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Build

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

import PackageModel
@testable import SourceKitLSPAPI
import SPMBuildCore
import _InternalTestSupport
import XCTest

final class SourceKitLSPAPITests: XCTestCase {
    func testBasicSwiftPackage() async throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/exe/README.md",
            "/Pkg/Sources/exe/exe.docc/GettingStarted.md",
            "/Pkg/Sources/exe/Resources/some_file.txt",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Sources/lib/README.md",
            "/Pkg/Sources/lib/lib.docc/GettingStarted.md",
            "/Pkg/Sources/lib/Resources/some_file.txt",
            "/Pkg/Plugins/plugin/plugin.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: .v5_10,
                    targets: [
                        TargetDescription(
                            name: "exe",
                            dependencies: ["lib"],
                            resources: [.init(rule: .copy, path: "Resources/some_file.txt")],
                            type: .executable
                        ),
                        TargetDescription(
                            name: "lib",
                            dependencies: [],
                            resources: [.init(rule: .copy, path: "Resources/some_file.txt")]
                        ),
                        TargetDescription(name: "plugin", type: .plugin, pluginCapability: .buildTool)
                    ]),
            ],
            observabilityScope: observability.topScope,
            traitConfiguration: nil
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                shouldLinkStaticSwiftStdlib: true
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                shouldLinkStaticSwiftStdlib: true
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        try description.checkArguments(
            for: "exe",
            graph: graph,
            partialArguments: [
                "-module-name", "exe",
                "-package-name", "pkg",
                "-emit-dependencies",
                "-emit-module",
                "-emit-module-path", AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/Modules/exe.swiftmodule").pathString
            ],
            resources: [.init(filePath: "/Pkg/Sources/exe/Resources/some_file.txt")],
            ignoredFiles: [.init(filePath: "/Pkg/Sources/exe/exe.docc")],
            otherFiles: [.init(filePath: "/Pkg/Sources/exe/README.md")],
            isPartOfRootPackage: true
        )
        try description.checkArguments(
            for: "lib",
            graph: graph,
            partialArguments: [
                "-module-name", "lib",
                "-package-name", "pkg",
                "-emit-dependencies",
                "-emit-module",
                "-emit-module-path", AbsolutePath("/path/to/build/\(plan.destinationBuildParameters.triple)/debug/Modules/lib.swiftmodule").pathString
            ],
            resources: [.init(filePath: "/Pkg/Sources/lib/Resources/some_file.txt")],
            ignoredFiles: [.init(filePath: "/Pkg/Sources/lib/lib.docc")],
            otherFiles: [.init(filePath: "/Pkg/Sources/lib/README.md")],
            isPartOfRootPackage: true
        )
        try description.checkArguments(
            for: "plugin",
            graph: graph,
            partialArguments: [
                "-I", AbsolutePath("/fake/manifestLib/path").pathString
            ],
            isPartOfRootPackage: true,
            destination: .host
        )
    }

    func testModuleTraversal() async throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift",
            "/Pkg/Plugins/plugin/plugin.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: []),
                        TargetDescription(
                            name: "plugin",
                            dependencies: ["exe"],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope,
            traitConfiguration: nil
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                shouldLinkStaticSwiftStdlib: true
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                shouldLinkStaticSwiftStdlib: true
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        struct Result: Equatable {
            let moduleName: String
            let moduleDestination: BuildDestination
            let parentName: String?
            let parentDestination: BuildDestination?
        }

        var results: [Result] = []
        description.traverseModules { current, parent in
            results.append(
                Result(
                    moduleName: current.name,
                    moduleDestination: current.destination,
                    parentName: parent?.name,
                    parentDestination: parent?.destination
                )
            )
        }

        XCTAssertEqual(
            results,
            [
                Result(moduleName: "lib", moduleDestination: .target, parentName: nil, parentDestination: nil),
                Result(moduleName: "plugin", moduleDestination: .host, parentName: nil, parentDestination: nil),
                Result(moduleName: "exe", moduleDestination: .host, parentName: "plugin", parentDestination: .host),
                Result(moduleName: "lib", moduleDestination: .host, parentName: "exe", parentDestination: .host),
                Result(moduleName: "exe", moduleDestination: .target, parentName: nil, parentDestination: nil),
                Result(moduleName: "lib", moduleDestination: .target, parentName: "exe", parentDestination: .target),
            ]
        )
    }

    func testModuleTraversalRecordsDependencyOfVisitedNode() async throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
            "/Pkg/Sources/exe/main.swift",
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    targets: [
                        TargetDescription(name: "exe", dependencies: ["lib"]),
                        TargetDescription(name: "lib", dependencies: [])
                    ]
                ),
            ],
            observabilityScope: observability.topScope,
            traitConfiguration: nil
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                shouldLinkStaticSwiftStdlib: true
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                shouldLinkStaticSwiftStdlib: true
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        struct Result: Equatable {
            let moduleName: String
            let parentName: String?
        }

        var results: [Result] = []
        description.traverseModules { current, parent in
            results.append(Result(moduleName: current.name, parentName: parent?.name))
        }

        XCTAssertEqual(
            results,
            [
                Result(moduleName: "lib", parentName: nil),
                Result(moduleName: "exe", parentName: nil),
                Result(moduleName: "lib", parentName: "exe"),
            ]
        )
    }

    func testLoadPackage() async throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/lib/lib.swift"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: .v5_10,
                    targets: [
                        TargetDescription(
                            name: "lib",
                            dependencies: []
                        )
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)

        let destinationBuildParameters = mockBuildParameters(destination: .target)
        try await withTemporaryDirectory { tmpDir in
            let pluginConfiguration = PluginConfiguration(
                scriptRunner: DefaultPluginScriptRunner(
                    fileSystem: fs,
                    cacheDir: tmpDir.appending("cache"),
                    toolchain: try UserToolchain.default
                ),
                workDirectory: tmpDir.appending("work"),
                disableSandbox: false
            )
            let scratchDirectory = tmpDir.appending(".build")

            let loaded = try await BuildDescription.load(
                destinationBuildParameters: destinationBuildParameters,
                toolsBuildParameters: mockBuildParameters(destination: .host),
                packageGraph: graph,
                pluginConfiguration: pluginConfiguration,
                traitConfiguration: TraitConfiguration(),
                disableSandbox: false,
                scratchDirectory: scratchDirectory.asURL,
                fileSystem: fs,
                observabilityScope: observability.topScope
            )

            try loaded.description.checkArguments(
                for: "lib",
                graph: graph,
                partialArguments: [
                    "-module-name", "lib",
                    "-package-name", "pkg",
                    "-emit-dependencies",
                    "-emit-module",
                    "-emit-module-path", AbsolutePath("/path/to/build/\(destinationBuildParameters.triple)/debug/Modules/lib.swiftmodule").pathString
                ],
                isPartOfRootPackage: true
            )
        }
    }

    func testClangOutputPaths() async throws {
        let fs = InMemoryFileSystem(emptyFiles:
            "/Pkg/Sources/lib/include/lib.h",
            "/Pkg/Sources/lib/lib.cpp"
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: .v5_10,
                    targets: [
                        TargetDescription(
                            name: "lib",
                            dependencies: []
                        )
                    ]),
            ],
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        let plan = try await BuildPlan(
            destinationBuildParameters: mockBuildParameters(
                destination: .target,
                shouldLinkStaticSwiftStdlib: true
            ),
            toolsBuildParameters: mockBuildParameters(
                destination: .host,
                shouldLinkStaticSwiftStdlib: true
            ),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let description = BuildDescription(buildPlan: plan)

        let target = try XCTUnwrap(description.getBuildTarget(for: XCTUnwrap(graph.module(for: "lib")), destination: .target))
        XCTAssertEqual(target.compiler, .clang)
        XCTAssertEqual(target.sources.count, 1)
        XCTAssertEqual(target.sources.last?.outputFile?.lastPathComponent, "lib.cpp.o")
    }
}

extension SourceKitLSPAPI.BuildDescription {
    @discardableResult func checkArguments(
        for targetName: String,
        graph: ModulesGraph,
        partialArguments: [String],
        resources: [URL] = [],
        ignoredFiles: [URL] = [],
        otherFiles: [URL] = [],
        isPartOfRootPackage: Bool,
        destination: BuildParameters.Destination = .target
    ) throws -> Bool {
        let target = try XCTUnwrap(graph.module(for: targetName))
        let buildTarget = try XCTUnwrap(self.getBuildTarget(for: target, destination: destination))

        XCTAssertEqual(buildTarget.resources, resources, "build target \(targetName) contains unexpected resource files")
        XCTAssertEqual(buildTarget.ignored, ignoredFiles, "build target \(targetName) contains unexpected ignored files")
        XCTAssertEqual(buildTarget.others, otherFiles, "build target \(targetName) contains unexpected other files")

        guard let source = buildTarget.sources.first?.sourceFile else {
            XCTFail("build target \(targetName) contains no source files")
            return false
        }

        let arguments = try buildTarget.compileArguments(for: source)
        let result = arguments.contains(partialArguments)

        XCTAssertTrue(result, "could not match \(partialArguments) to actual arguments \(arguments)")
        XCTAssertEqual(buildTarget.isPartOfRootPackage, isPartOfRootPackage)
        return result
    }
}
