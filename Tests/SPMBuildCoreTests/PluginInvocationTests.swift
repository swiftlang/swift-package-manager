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
                writableDirectories: [AbsolutePath],
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
                syntax error
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
            XCTAssert(observability.diagnostics.isEmpty, "\(observability.diagnostics)")
            XCTAssert(packageGraph.packages.count == 1, "\(packageGraph.packages)")
            
            // Find the build tool plugin.
            let buildToolPlugin = try XCTUnwrap(packageGraph.packages[0].targets.first{ $0.type == .plugin })
            XCTAssertEqual(buildToolPlugin.name, "MyPlugin")
            
            // Try to compile the broken plugin script and check that we get the expected error.
            let pluginCacheDir = tmpPath.appending(component: "plugin-cache")
            let pluginScriptRunner = DefaultPluginScriptRunner(cacheDir: pluginCacheDir, toolchain: ToolchainConfiguration.default)
            XCTAssertThrowsError(try tsc_await { pluginScriptRunner.compilePluginScript(
                sources: buildToolPlugin.sources,
                toolsVersion: .currentToolsVersion,
                observabilityScope: observability.topScope,
                callbackQueue: DispatchQueue(label: "plugin-compilation"),
                completion: $0)
            }) { error in
                guard case DefaultPluginScriptRunnerError.compilationFailed(let result) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssert(result.compilerResult.exitStatus == .terminated(code: 1), "\(result.compilerResult.exitStatus)")
                XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
                XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")
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
            
            // Try to compile the fixed plugin. This time it should succeed but we expect a warning.
            let result = try tsc_await { pluginScriptRunner.compilePluginScript(
                sources: buildToolPlugin.sources,
                toolsVersion: .currentToolsVersion,
                observabilityScope: observability.topScope,
                callbackQueue: DispatchQueue(label: "plugin-compilation"),
                completion: $0) }
            
            // Now we expect compilation to succeed but with a warning.
            XCTAssert(result.compilerResult.exitStatus == .terminated(code: 0), "\(result.compilerResult.exitStatus)")
            XCTAssert(result.compiledExecutable.components.contains("plugin-cache"), "\(result.compiledExecutable.pathString)")
            XCTAssert(result.diagnosticsFile.suffix == ".dia", "\(result.diagnosticsFile.pathString)")
            let contents = try localFileSystem.readFileContents(result.diagnosticsFile)
            let diags = try SerializedDiagnostics(bytes: contents)
            XCTAssertEqual(diags.diagnostics.count, 1)
            let warningDiag = try XCTUnwrap(diags.diagnostics.first)
            XCTAssertTrue(warningDiag.text.hasPrefix("variable \'unused\' was never used"), "\(warningDiag)")
        }
    }
}
