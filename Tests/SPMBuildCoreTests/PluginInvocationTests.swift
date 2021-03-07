/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic

import PackageGraph
import PackageModel
@testable import SPMBuildCore
import SPMTestSupport


class PluginInvocationTests: XCTestCase {
    
    func testBasics() throws {
        // Construct a canned file system and package graph with a single package and a library that uses a plugin that uses a tool.
        let fileSystem = InMemoryFileSystem(emptyFiles:
            "/Foo/Sources/Foo/source.swift",
            "/Foo/Sources/Foo/SomeFile.abc",
            "/Foo/Sources/FooExt/source.swift",
            "/Foo/Sources/FooTool/source.swift"
        )
        let diagnostics = DiagnosticsEngine()
        let graph = try loadPackageGraph(fs: fileSystem, diagnostics: diagnostics,
            manifests: [
                Manifest.createV4Manifest(
                    name: "Foo",
                    path: "/Foo",
                    packageKind: .root,
                    packageLocation: "/Foo",
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
                            dependencies: ["FooExt"],
                            type: .regular
                        ),
                        TargetDescription(
                            name: "FooExt",
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
            allowPluginTargets: true
        )
        
        // Check the basic integrity before running plugins.
        XCTAssertNoDiagnostics(diagnostics)
        PackageGraphTester(graph) { graph in
            graph.check(packages: "Foo")
            graph.check(targets: "Foo", "FooExt", "FooTool")
            graph.checkTarget("Foo") { target in
                target.check(dependencies: "FooExt")
            }
            graph.checkTarget("FooExt") { target in
                target.check(type: .plugin)
                target.check(dependencies: "FooTool")
            }
            graph.checkTarget("FooTool") { target in
                target.check(type: .executable)
            }
        }
        
        // A fake PluginScriptRunner that just checks the input conditions and returns canned output.
        struct MockPluginScriptRunner: PluginScriptRunner {
            func runPluginScript(
                sources: Sources,
                inputJSON: Data,
                toolsVersion: ToolsVersion,
                diagnostics: DiagnosticsEngine,
                fileSystem: FileSystem
            ) throws -> (outputJSON: Data, stdoutText: Data) {
                // Check that we were given the right sources.
                XCTAssertEqual(sources.root, AbsolutePath("/Foo/Sources/FooExt"))
                XCTAssertEqual(sources.relativePaths, [RelativePath("source.swift")])
                
                // Deserialize and check the input.
                let decoder = JSONDecoder()
                let context = try decoder.decode(PluginScriptRunnerInput.self, from: inputJSON)
                XCTAssertEqual(context.targetName, "Foo")
                
                // Emit and return a serialized output PluginInvocationResult JSON.
                let encoder = JSONEncoder()
                let result = PluginScriptRunnerOutput(
                    version: 1,
                    diagnostics: [
                        .init(
                            severity: .warning,
                            message: "A warning",
                            file: "/Foo/Sources/Foo/SomeFile.abc",
                            line: 42
                        )
                    ],
                    commands: [
                        .init(
                            displayName: "Do something",
                            executable: "/bin/FooTool",
                            arguments: ["-c", "/Foo/Sources/Foo/SomeFile.abc"],
                            workingDirectory: "/Foo/Sources/Foo",
                            environment: [
                                "X": "Y"
                            ],
                            inputPaths: [],
                            outputPaths: []
                        )
                ])
                let outputJSON = try encoder.encode(result)
                return (outputJSON: outputJSON, stdoutText: "Hello Plugin!".data(using: .utf8)!)
            }
        }
        
        // Construct a canned input and run plugins using our MockPluginScriptRunner().
        let buildEnv = BuildEnvironment(platform: .macOS, configuration: .debug)
        let execsDir = AbsolutePath("/Foo/.build/debug")
        let outputDir = AbsolutePath("/Foo/.build")
        let pluginRunner = MockPluginScriptRunner()
        let results = try graph.invokePlugins(buildEnvironment: buildEnv, execsDir: execsDir, outputDir: outputDir, pluginScriptRunner: pluginRunner, diagnostics: diagnostics, fileSystem: fileSystem)
        
        // Check the canned output to make sure nothing was lost in transport.
        XCTAssertNoDiagnostics(diagnostics)
        XCTAssertEqual(results.count, 1)
        let (evalTarget, evalResults) = try XCTUnwrap(results.first)
        XCTAssertEqual(evalTarget.name, "Foo")
        
        XCTAssertEqual(evalResults.count, 1)
        let evalFirstResult = try XCTUnwrap(evalResults.first)
        XCTAssertEqual(evalFirstResult.commands.count, 1)
        let evalFirstCommand = try XCTUnwrap(evalFirstResult.commands.first)
        if case .buildToolCommand(let name, let exec, let args, let env, let wdir, let inputs, let outputs) = evalFirstCommand {
            XCTAssertEqual(name, "Do something")
            XCTAssertEqual(exec, "/bin/FooTool")
            XCTAssertEqual(args, ["-c", "/Foo/Sources/Foo/SomeFile.abc"])
            XCTAssertEqual(wdir, AbsolutePath("/Foo/Sources/Foo"))
            XCTAssertEqual(env, ["X": "Y"])
            XCTAssertEqual(inputs, [])
            XCTAssertEqual(outputs, [])
        }
        else {
            XCTFail("The command provided by the plugin didn't match expectations")
        }
        
        XCTAssertEqual(evalFirstResult.diagnostics.count, 1)
        let evalFirstDiagnostic = try XCTUnwrap(evalFirstResult.diagnostics.first)
        XCTAssertEqual(evalFirstDiagnostic.behavior, .warning)
        XCTAssertEqual(evalFirstDiagnostic.message.text, "A warning")
        XCTAssertEqual(evalFirstDiagnostic.location.description, "/Foo/Sources/Foo/SomeFile.abc:42")

        XCTAssertEqual(evalFirstResult.textOutput, "Hello Plugin!")
    }
}
