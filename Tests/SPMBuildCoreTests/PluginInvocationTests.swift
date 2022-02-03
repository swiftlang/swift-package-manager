/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
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
import TSCUtility
import Workspace
import XCTest

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
            func runPluginScript(
                sources: Sources,
                input: PluginScriptRunnerInput,
                toolsVersion: ToolsVersion,
                workingDirectory: AbsolutePath,
                writableDirectories: [AbsolutePath],
                readOnlyDirectories: [AbsolutePath],
                fileSystem: FileSystem,
                observabilityScope: ObservabilityScope,
                callbackQueue: DispatchQueue,
                delegate: PluginInvocationDelegate,
                completion: @escaping (Result<Bool, Error>) -> Void
            ) {
                // Check that we were given the right sources.
                XCTAssertEqual(sources.root, AbsolutePath("/Foo/Plugins/FooPlugin"))
                XCTAssertEqual(sources.relativePaths, [RelativePath("source.swift")])

                // Check the input structure we received.
                XCTAssertEqual(input.products.count, 2, "unexpected products: \(dump(input.products))")
                XCTAssertEqual(input.products[0].name, "Foo", "unexpected products: \(dump(input.products))")
                XCTAssertEqual(input.products[0].targetIds.count, 1, "unexpected product targets: \(dump(input.products[0].targetIds))")
                XCTAssertEqual(input.products[1].name, "FooTool", "unexpected products: \(dump(input.products))")
                XCTAssertEqual(input.products[1].targetIds.count, 1, "unexpected product targets: \(dump(input.products[1].targetIds))")
                XCTAssertEqual(input.targets.count, 2, "unexpected targets: \(dump(input.targets))")
                XCTAssertEqual(input.targets[0].name, "Foo", "unexpected targets: \(dump(input.targets))")
                XCTAssertEqual(input.targets[0].dependencies.count, 0, "unexpected target dependencies: \(dump(input.targets[0].dependencies))")
                XCTAssertEqual(input.targets[1].name, "FooTool", "unexpected targets: \(dump(input.targets))")
                XCTAssertEqual(input.targets[1].dependencies.count, 0, "unexpected target dependencies: \(dump(input.targets[1].dependencies))")

                // Pretend the plugin emitted some output.
                callbackQueue.sync {
                    delegate.pluginEmittedOutput(Data("Hello Plugin!".utf8))
                }
                
                // Pretend it emitted a warning.
                callbackQueue.sync {
                    var locationMetadata = ObservabilityMetadata()
                    locationMetadata.fileLocation = .init(AbsolutePath("/Foo/Sources/Foo/SomeFile.abc"), line: 42)
                    delegate.pluginEmittedDiagnostic(.warning("A warning", metadata: locationMetadata))
                }
                
                // Pretend it defined a build command.
                callbackQueue.sync {
                    delegate.pluginDefinedBuildCommand(
                        displayName: "Do something",
                        executable: AbsolutePath("/bin/FooTool"),
                        arguments: ["-c", "/Foo/Sources/Foo/SomeFile.abc"],
                        environment: [
                            "X": "Y"
                        ],
                        workingDirectory: AbsolutePath("/Foo/Sources/Foo"),
                        inputFiles: [],
                        outputFiles: [])
                }
                
                // Finally, invoke the completion handler.
                callbackQueue.sync {
                    completion(.success(true))
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
            try localFileSystem.writeFileContents(packageDir.appending(component: "Package.swift")) {
                $0 <<< """
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
                """
            }
            try localFileSystem.writeFileContents(packageDir.appending(components: "Sources", "MyLibrary", "library.swift")) {
                $0 <<< """
                public func Foo() { }
                """
            }
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift")) {
                $0 <<< """
                import PackagePlugin

                @main
                struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        // missing return statement
                    }
                }
                """
            }

            // Load a workspace from the package.
            let observability = ObservabilitySystem.makeForTesting()
            let workspace = try Workspace(
                fileSystem: localFileSystem,
                location: .init(forRootPackage: packageDir, fileSystem: localFileSystem),
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
            let pluginScriptRunner = DefaultPluginScriptRunner(cacheDir: pluginCacheDir, toolchain: ToolchainConfiguration.default)

            // Try to compile the broken plugin script.
            do {
                var compilationResult: PluginCompilationResult? = .none
                XCTAssertThrowsError(try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)
                ) { error in
                    // Check that we got the expected error, and capture the result.
                    guard case DefaultPluginScriptRunnerError.compilationFailed(let result) = error else {
                        return XCTFail("unexpected error: \(error)")
                    }
                    compilationResult = result
                }

                // This should invoke the compiler but should fail.
                let result = try XCTUnwrap(compilationResult)
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
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift")) {
                $0 <<< """
                import PackagePlugin
                
                @main
                struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        var unused: Int
                        return []
                    }
                }
                """
            }
            
            // Try to compile the fixed plugin.
            let firstExecModTime: Date
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should invoke the compiler and this time should succeed.
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
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift")) {
                $0 <<< """
                import PackagePlugin

                @main
                struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        return []
                    }
                }
                """
            }

            // Recompile the plugin again.
            let thirdExecModTime: Date
            do {
                let result = try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)

                // This should invoke the compiler and not use the cache.
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
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "MyPlugin", "plugin.swift")) {
                $0 <<< """
                import PackagePlugin

                @main
                struct MyBuildToolPlugin: BuildToolPlugin {
                    func createBuildCommands(
                        context: PluginContext,
                        target: Target
                    ) throws -> [Command] {
                        return nil  // returning the wrong type
                    }
                }
                """
            }

            // Recompile the plugin again.
            do {
                var compilationResult: PluginCompilationResult? = .none
                XCTAssertThrowsError(try pluginScriptRunner.compilePluginScript(
                    sources: buildToolPlugin.sources,
                    toolsVersion: buildToolPlugin.apiVersion,
                    observabilityScope: observability.topScope)
                ) { error in
                    // Check that we got the expected error, and capture the result.
                    guard case DefaultPluginScriptRunnerError.compilationFailed(let result) = error else {
                        return XCTFail("unexpected error: \(error)")
                    }
                    compilationResult = result
                }

                // This should again invoke the compiler but should fail.
                let result = try XCTUnwrap(compilationResult)
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
