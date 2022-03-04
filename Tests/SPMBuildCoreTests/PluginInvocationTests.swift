/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import PackageGraph
import PackageLoading
import PackageModel
@testable import SPMBuildCore
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

import struct TSCUtility.SerializedDiagnostics
import struct TSCUtility.Triple

class PluginInvocationTests: XCTestCase {

    func testBasics() throws {
        // Construct a canned file system and package graph with a single package and a library that uses a build tool plugin that invokes a tool.
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/Foo/Plugins/FooPlugin/source.swift",
            "/Foo/Sources/FooTool/source.swift",
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/Foo/SomeFile.abc"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fs: fileSystem,
            manifests: [
                Manifest.createRootManifest(
                    name: "Foo",
                    path: .init("/Foo"),
                    products: [
                        ProductDescription(
                            name: "Foo",
                            type: .library(.dynamic),
                            targets: ["Foo"]
                        )
                    ],
                    targets: [
                        TargetDescription(
                            name: "Foo",
                            type: .regular,
                            pluginUsages: [.plugin(name: "FooPlugin", package: nil)]
                        ),
                        TargetDescription(
                            name: "FooPlugin",
                            dependencies: ["FooTool"],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                        TargetDescription(
                            name: "FooTool",
                            dependencies: [],
                            type: .executable
                        ),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        // Check the basic integrity before running plugins.
        XCTAssertNoDiagnostics(observability.diagnostics)
        PackageGraphTester(graph) { graph in
            graph.check(packages: "Foo")
            graph.check(targets: "Foo", "FooPlugin", "FooTool")
            graph.checkTarget("Foo") { target in
                target.check(dependencies: "FooPlugin")
            }
            graph.checkTarget("FooPlugin") { target in
                target.check(type: .plugin)
                target.check(dependencies: "FooTool")
            }
            graph.checkTarget("FooTool") { target in
                target.check(type: .executable)
            }
        }

        // A fake PluginScriptRunner that just checks the input conditions and returns canned output.
        struct MockPluginScriptRunner: PluginScriptRunner {
            
            var hostTriple: Triple {
                return UserToolchain.default.triple
            }
            
            func compilePluginScript(sources: Sources, toolsVersion: ToolsVersion, observabilityScope: ObservabilityScope) throws -> PluginCompilationResult {
                throw StringError("unimplemented")
            }
            
            func runPluginScript(
                sources: Sources,
                initialMessage: Data,
                toolsVersion: ToolsVersion,
                workingDirectory: AbsolutePath,
                writableDirectories: [AbsolutePath],
                readOnlyDirectories: [AbsolutePath],
                fileSystem: FileSystem,
                observabilityScope: ObservabilityScope,
                callbackQueue: DispatchQueue,
                delegate: PluginScriptRunnerDelegate,
                completion: @escaping (Result<Int32, Error>) -> Void
            ) {
                // Check that we were given the right sources.
                XCTAssertEqual(sources.root, AbsolutePath("/Foo/Plugins/FooPlugin"))
                XCTAssertEqual(sources.relativePaths, [RelativePath("source.swift")])

                do {
                    // Pretend the plugin emitted some output.
                    callbackQueue.sync {
                        delegate.handleOutput(data: Data("Hello Plugin!".utf8))
                    }
                    
                    // Pretend it emitted a warning.
                    try callbackQueue.sync {
                        let message = Data("""
                        {   "emitDiagnostic": {
                                "severity": "warning",
                                "message": "A warning",
                                "file": "/Foo/Sources/Foo/SomeFile.abc",
                                "line": 42
                            }
                        }
                        """.utf8)
                        try delegate.handleMessage(data: message, responder: { _ in })
                    }

                    // Pretend it defined a build command.
                    try callbackQueue.sync {
                        let message = Data("""
                        {   "defineBuildCommand": {
                                "configuration": {
                                    "displayName": "Do something",
                                    "executable": "/bin/FooTool",
                                    "arguments": [
                                        "-c", "/Foo/Sources/Foo/SomeFile.abc"
                                    ],
                                    "workingDirectory": "/Foo/Sources/Foo",
                                    "environment": {
                                        "X": "Y"
                                    },
                                },
                                "inputFiles": [
                                ],
                                "outputFiles": [
                                ]
                            }
                        }
                        """.utf8)
                        try delegate.handleMessage(data: message, responder: { _ in })
                    }
                }
                catch {
                    callbackQueue.sync {
                        completion(.failure(error))
                    }
                }

                // If we get this far we succeded, so invoke the completion handler.
                callbackQueue.sync {
                    completion(.success(0))
                }
            }
        }

        // Construct a canned input and run plugins using our MockPluginScriptRunner().
        let outputDir = AbsolutePath("/Foo/.build")
        let builtToolsDir = AbsolutePath("/Foo/.build/debug")
        let pluginRunner = MockPluginScriptRunner()
        let results = try graph.invokeBuildToolPlugins(
            outputDir: outputDir,
            builtToolsDir: builtToolsDir,
            buildEnvironment: BuildEnvironment(platform: .macOS, configuration: .debug),
            toolSearchDirectories: [UserToolchain.default.swiftCompilerPath.parentDirectory],
            pluginScriptRunner: pluginRunner,
            observabilityScope: observability.topScope,
            fileSystem: fileSystem
        )

        // Check the canned output to make sure nothing was lost in transport.
        XCTAssertNoDiagnostics(observability.diagnostics)
        XCTAssertEqual(results.count, 1)
        let (evalTarget, evalResults) = try XCTUnwrap(results.first)
        XCTAssertEqual(evalTarget.name, "Foo")

        XCTAssertEqual(evalResults.count, 1)
        let evalFirstResult = try XCTUnwrap(evalResults.first)
        XCTAssertEqual(evalFirstResult.prebuildCommands.count, 0)
        XCTAssertEqual(evalFirstResult.buildCommands.count, 1)
        let evalFirstCommand = try XCTUnwrap(evalFirstResult.buildCommands.first)
        XCTAssertEqual(evalFirstCommand.configuration.displayName, "Do something")
        XCTAssertEqual(evalFirstCommand.configuration.executable, AbsolutePath("/bin/FooTool"))
        XCTAssertEqual(evalFirstCommand.configuration.arguments, ["-c", "/Foo/Sources/Foo/SomeFile.abc"])
        XCTAssertEqual(evalFirstCommand.configuration.environment, ["X": "Y"])
        XCTAssertEqual(evalFirstCommand.configuration.workingDirectory, AbsolutePath("/Foo/Sources/Foo"))
        XCTAssertEqual(evalFirstCommand.inputFiles, [])
        XCTAssertEqual(evalFirstCommand.outputFiles, [])

        XCTAssertEqual(evalFirstResult.diagnostics.count, 1)
        let evalFirstDiagnostic = try XCTUnwrap(evalFirstResult.diagnostics.first)
        XCTAssertEqual(evalFirstDiagnostic.severity, .warning)
        XCTAssertEqual(evalFirstDiagnostic.message, "A warning")
        XCTAssertEqual(evalFirstDiagnostic.metadata?.fileLocation, FileLocation(.init("/Foo/Sources/Foo/SomeFile.abc"), line: 42))

        XCTAssertEqual(evalFirstResult.textOutput, "Hello Plugin!")
    }
    
    func testCompilationDiagnostics() throws {
        try testWithTemporaryDirectory { tmpPath in
            // Create a sample package with a library target and a plugin.
            let packageDir = tmpPath.appending(components: "MyPackage")
            try localFileSystem.createDirectory(packageDir, recursive: true)
            try localFileSystem.writeFileContents(packageDir.appending(component: "Package.swift"), string: """
                // swift-tools-version: 5.6
                import PackageDescription
                let package = Package(
                    name: "MyPackage",
                    targets: [
                        .target(
                            name: "MyLibrary",
                            plugins: [
                                "MyPlugin",
                            ]
                        ),
                        .plugin(
                            name: "MyPlugin",
                            capability: .buildTool()
                        ),
                    ]
                )
                """)
            
            let myLibraryTargetDir = packageDir.appending(components: "Sources", "MyLibrary")
            try localFileSystem.createDirectory(myLibraryTargetDir, recursive: true)
            try localFileSystem.writeFileContents(myLibraryTargetDir.appending(component: "library.swift"), string: """
                public func Foo() { }
                """)
            
            let myPluginTargetDir = packageDir.appending(components: "Plugins", "MyPlugin")
            try localFileSystem.createDirectory(myPluginTargetDir, recursive: true)
            try localFileSystem.writeFileContents(myPluginTargetDir.appending(component: "plugin.swift"), string: """
                import PackagePlugin
                @main struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        // missing return statement
                    }
                }
                """)

            // Load a workspace from the package.
            let observability = ObservabilitySystem.makeForTesting()
            let workspace = try Workspace(
                fileSystem: localFileSystem,
                forRootPackage: packageDir,
                customManifestLoader: ManifestLoader(toolchain: ToolchainConfiguration.default),
                delegate: MockWorkspaceDelegate()
            )
            
            // Load the root manifest.
            let rootInput = PackageGraphRootInput(packages: [packageDir], dependencies: [])
            let rootManifests = try tsc_await {
                workspace.loadRootManifests(
                    packages: rootInput.packages,
                    observabilityScope: observability.topScope,
                    completion: $0
                )
            }
            XCTAssert(rootManifests.count == 1, "\(rootManifests)")

            // Load the package graph.
            let packageGraph = try workspace.loadPackageGraph(rootInput: rootInput, observabilityScope: observability.topScope)
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssert(packageGraph.packages.count == 1, "\(packageGraph.packages)")
            
            // Find the build tool plugin.
            let buildToolPlugin = try XCTUnwrap(packageGraph.packages[0].targets.map(\.underlyingTarget).first{ $0.name == "MyPlugin" } as? PluginTarget)
            XCTAssertEqual(buildToolPlugin.name, "MyPlugin")
            XCTAssertEqual(buildToolPlugin.capability, .buildTool)

            // Create a plugin script runner for the duration of the test.
            let pluginCacheDir = tmpPath.appending(component: "plugin-cache")
            let pluginScriptRunner = DefaultPluginScriptRunner(
                fileSystem: localFileSystem,
                cacheDir: pluginCacheDir,
                toolchain: ToolchainConfiguration.default
            )

            // Try to compile the broken plugin script.
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should invoke the compiler but should fail.
                XCTAssert(result.succeeded == false)
                XCTAssert(result.wasCached == false)
                XCTAssert(result.compilerResult?.exitStatus == .terminated(code: 1), "\(String(describing: result.compilerResult?.exitStatus))")
                XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
                XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")

                // Check the serialized diagnostics. We should have an error.
                let diaFileContents = try localFileSystem.readFileContents(result.diagnosticsFile)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)
                XCTAssertEqual(diagnosticsSet.diagnostics.count, 1)
                let errorDiagnostic = try XCTUnwrap(diagnosticsSet.diagnostics.first)
                XCTAssertTrue(errorDiagnostic.text.hasPrefix("missing return"), "\(errorDiagnostic)")

                // Check that the executable file doesn't exist.
                XCTAssertFalse(localFileSystem.exists(result.compiledExecutable), "\(result.compiledExecutable.pathString)")
            }

            // Now replace the plugin script source with syntactically valid contents that still produces a warning.
            try localFileSystem.writeFileContents(myPluginTargetDir.appending(component: "plugin.swift"), string: """
                import PackagePlugin
                @main struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        var unused: Int
                        return []
                    }
                }
                """)
            
            // Try to compile the fixed plugin.
            let firstExecModTime: Date
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should invoke the compiler and this time should succeed.
                XCTAssert(result.succeeded == true)
                XCTAssert(result.wasCached == false)
                XCTAssert(result.compilerResult?.exitStatus == .terminated(code: 0), "\(String(describing: result.compilerResult?.exitStatus))")
                XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
                XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")

                // Check the serialized diagnostics. We should no longer have an error but now have a warning.
                let diaFileContents = try localFileSystem.readFileContents(result.diagnosticsFile)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)
                XCTAssertEqual(diagnosticsSet.diagnostics.count, 1)
                let warningDiagnostic = try XCTUnwrap(diagnosticsSet.diagnostics.first)
                XCTAssertTrue(warningDiagnostic.text.hasPrefix("variable \'unused\' was never used"), "\(warningDiagnostic)")

                // Check that the executable file exists.
                XCTAssertTrue(localFileSystem.exists(result.compiledExecutable), "\(result.compiledExecutable.pathString)")

                // Capture the timestamp of the executable so we can compare it later.
                firstExecModTime = try localFileSystem.getFileInfo(result.compiledExecutable).modTime
            }

            // Recompile the command plugin again without changing its source code.
            let secondExecModTime: Date
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should not invoke the compiler (just reuse the cached executable).
                XCTAssert(result.succeeded == true)
                XCTAssert(result.wasCached == true)
                XCTAssert(result.compilerResult == nil, "\(String(describing: result.compilerResult))")
                XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
                XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")

                // Check that the diagnostics still have the same warning as before.
                let diaFileContents = try localFileSystem.readFileContents(result.diagnosticsFile)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)
                XCTAssertEqual(diagnosticsSet.diagnostics.count, 1)
                let warningDiagnostic = try XCTUnwrap(diagnosticsSet.diagnostics.first)
                XCTAssertTrue(warningDiagnostic.text.hasPrefix("variable \'unused\' was never used"), "\(warningDiagnostic)")

                // Check that the executable file exists.
                XCTAssertTrue(localFileSystem.exists(result.compiledExecutable), "\(result.compiledExecutable.pathString)")

                // Check that the timestamp hasn't changed (at least a mild indication that it wasn't recompiled).
                secondExecModTime = try localFileSystem.getFileInfo(result.compiledExecutable).modTime
                XCTAssert(secondExecModTime == firstExecModTime, "firstExecModTime: \(firstExecModTime), secondExecModTime: \(secondExecModTime)")
            }

            // Now replace the plugin script source with syntactically valid contents that no longer produces a warning.
            try localFileSystem.writeFileContents(myPluginTargetDir.appending(component: "plugin.swift"), string: """
                import PackagePlugin
                @main struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        return []
                    }
                }
                """)

            // Recompile the plugin again.
            let thirdExecModTime: Date
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should invoke the compiler and not use the cache.
                XCTAssert(result.succeeded == true)
                XCTAssert(result.wasCached == false)
                XCTAssert(result.compilerResult?.exitStatus == .terminated(code: 0), "\(String(describing: result.compilerResult?.exitStatus))")
                XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
                XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")

                // Check that the diagnostics no longer have a warning.
                let diaFileContents = try localFileSystem.readFileContents(result.diagnosticsFile)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)
                XCTAssertEqual(diagnosticsSet.diagnostics.count, 0)

                // Check that the executable file exists.
                XCTAssertTrue(localFileSystem.exists(result.compiledExecutable), "\(result.compiledExecutable.pathString)")

                // Check that the timestamp has changed (at least a mild indication that it was recompiled).
                thirdExecModTime = try localFileSystem.getFileInfo(result.compiledExecutable).modTime
                XCTAssert(thirdExecModTime != firstExecModTime, "thirdExecModTime: \(thirdExecModTime), firstExecModTime: \(firstExecModTime)")
                XCTAssert(thirdExecModTime != secondExecModTime, "thirdExecModTime: \(thirdExecModTime), secondExecModTime: \(secondExecModTime)")
            }

            // Now replace the plugin script source with a broken one again.
            try localFileSystem.writeFileContents(myPluginTargetDir.appending(component: "plugin.swift"), string: """
                import PackagePlugin
                @main struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        return nil  // returning the wrong type
                    }
                }
                """)

            // Recompile the plugin again.
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should again invoke the compiler but should fail.
                XCTAssert(result.succeeded == false)
                XCTAssert(result.wasCached == false)
                XCTAssert(result.compilerResult?.exitStatus == .terminated(code: 1), "\(String(describing: result.compilerResult?.exitStatus))")
                XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
                XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")

                // Check that the diagnostics. We should have a different error than the original one.
                let diaFileContents = try localFileSystem.readFileContents(result.diagnosticsFile)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)
                XCTAssertEqual(diagnosticsSet.diagnostics.count, 1)
                let errorDiagnostic = try XCTUnwrap(diagnosticsSet.diagnostics.first)
                XCTAssertTrue(errorDiagnostic.text.hasPrefix("'nil' is incompatible with return type"), "\(errorDiagnostic)")

                // Check that the executable file no longer exists.
                XCTAssertFalse(localFileSystem.exists(result.compiledExecutable), "\(result.compiledExecutable.pathString)")
            }
        }
    }
}
