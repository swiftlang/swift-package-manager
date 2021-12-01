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

class PluginTests: XCTestCase {
    
    func testUseOfBuildToolPluginTargetByExecutableInSamePackage() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif
        
        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MySourceGenPlugin"), configuration: .Debug, extraArgs: ["--product", "MyLocalTool"])
                XCTAssert(stdout.contains("Linking MySourceGenBuildTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testUseOfBuildToolPluginProductByExecutableAcrossPackages() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MySourceGenClient"), configuration: .Debug, extraArgs: ["--product", "MyTool"])
                XCTAssert(stdout.contains("Linking MySourceGenBuildTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testUseOfPrebuildPluginTargetByExecutableAcrossPackages() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MySourceGenPlugin"), configuration: .Debug, extraArgs: ["--product", "MyOtherLocalTool"])
                XCTAssert(stdout.contains("Compiling MyOtherLocalTool bar.swift"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Compiling MyOtherLocalTool baz.swift"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyOtherLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testUseOfPluginWithInternalExecutable() {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        fixture(name: "Miscellaneous/Plugins") { path in
            let (stdout, _) = try executeSwiftBuild(path.appending(component: "ClientOfPluginWithInternalExecutable"))
            XCTAssert(stdout.contains("Compiling PluginExecutable main.swift"), "stdout:\n\(stdout)")
            XCTAssert(stdout.contains("Linking PluginExecutable"), "stdout:\n\(stdout)")
            XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
            XCTAssert(stdout.contains("Compiling RootTarget foo.swift"), "stdout:\n\(stdout)")
            XCTAssert(stdout.contains("Linking RootTarget"), "stdout:\n\(stdout)")
            XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
        }
    }

    func testInternalExecutableAvailableOnlyToPlugin() {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "InvalidUseOfInternalPluginExecutable"))
                XCTFail("Illegally used internal executable.\nstdout:\n\(stdout)")
            }
            catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssert(
                    stderr.contains(
                        "product 'PluginExecutable' required by package 'invaliduseofinternalpluginexecutable' target 'RootTarget' not found in package 'PluginWithInternalExecutable'."
                    ),
                    "stderr:\n\(stderr)"
                )
            }
        }
    }

    func testContrivedTestCases() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif
        
        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "ContrivedTestPlugin"), configuration: .Debug, extraArgs: ["--product", "MyLocalTool"])
                XCTAssert(stdout.contains("Linking MySourceGenBuildTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Generating foo.swift from foo.dat"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
    }

    func testPluginScriptSandbox() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        #if os(macOS)
        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "SandboxTesterPlugin"), configuration: .Debug, extraArgs: ["--product", "MyLocalTool"])
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
        #endif
    }

    func testUseOfVendedBinaryTool() throws {
        // Check if the host compiler supports the '-entry-point-function-name' flag.  It's not needed for this test but is needed to build any executable from a package that uses tools version 5.5.
        #if swift(<5.5)
        try XCTSkipIf(true, "skipping because host compiler doesn't support '-entry-point-function-name'")
        #endif

        #if os(macOS)
        fixture(name: "Miscellaneous/Plugins") { path in
            do {
                let (stdout, _) = try executeSwiftBuild(path.appending(component: "MyBinaryToolPlugin"), configuration: .Debug, extraArgs: ["--product", "MyLocalTool"])
                XCTAssert(stdout.contains("Linking MyLocalTool"), "stdout:\n\(stdout)")
                XCTAssert(stdout.contains("Build complete!"), "stdout:\n\(stdout)")
            }
            catch {
                print(error)
                throw error
            }
        }
        #endif
    }
    
    func testCommandPluginInvocation() throws {
        try testWithTemporaryDirectory { tmpPath in
            // Create a sample package with a library target and a plugin.
            let packageDir = tmpPath.appending(components: "MyPackage")
            try localFileSystem.writeFileContents(packageDir.appending(component: "Package.swift")) {
                $0 <<< """
                // swift-tools-version: 999.0
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
                            capability: .command(
                                intent: .custom(verb: "mycmd", description: "What is mycmd anyway?"),
                                permissions: [.writeToPackageDirectory(reason: "YOLO")]
                            )
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
                    struct MyCommandPlugin: CommandPlugin {
                        func performCommand(
                            context: PluginContext,
                            targets: [Target],
                            arguments: [String]
                        ) throws {
                            print("This is MyCommandPlugin.")
                    
                            // Check that we can find a tool in the toolchain.
                            print("Looking for swiftc...")
                            let swiftc = try context.tool(named: "swiftc")
                            print("... found it at \\(swiftc)")
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
            XCTAssert(observability.diagnostics.isEmpty, "\(observability.diagnostics)")
            XCTAssert(packageGraph.packages.count == 1, "\(packageGraph.packages)")
            let package = try XCTUnwrap(packageGraph.packages.first)
            
            // Find the regular target in our test package.
            let libraryTarget = try XCTUnwrap(package.targets.map(\.underlyingTarget).first{ $0.name == "MyLibrary" } as? SwiftTarget)
            XCTAssertEqual(libraryTarget.type, .library)
            
            // Find the command plugin in our test package.
            let pluginTarget = try XCTUnwrap(package.targets.map(\.underlyingTarget).first{ $0.name == "MyPlugin" } as? PluginTarget)
            XCTAssertEqual(pluginTarget.type, .plugin)
            
            // Set up a delegate to handle callbacks from the command plugin.
            let delegateQueue = DispatchQueue(label: "plugin-invocation")
            class PluginDelegate: PluginInvocationDelegate {
                let delegateQueue: DispatchQueue
                var outputData = Data()

                init(delegateQueue: DispatchQueue) {
                    self.delegateQueue = delegateQueue
                }
                
                func pluginEmittedOutput(_ data: Data) {
                    dispatchPrecondition(condition: .onQueue(delegateQueue))
                    outputData.append(contentsOf: data)
                    print("🧩 \(String(decoding: data, as: UTF8.self))")
                }
                
                func pluginEmittedDiagnostic(_ diagnostic: Basics.Diagnostic) {
                    dispatchPrecondition(condition: .onQueue(delegateQueue))
                }
            }
            let pluginDelegate = PluginDelegate(delegateQueue: delegateQueue)

            // Invoke the command plugin.
            let pluginCacheDir = tmpPath.appending(component: "plugin-cache")
            let pluginOutputDir = tmpPath.appending(component: "plugin-output")
            let pluginScriptRunner = DefaultPluginScriptRunner(cacheDir: pluginCacheDir, toolchain: ToolchainConfiguration.default)
            let target = try XCTUnwrap(package.targets.first{ $0.underlyingTarget == libraryTarget })
            let _ = try tsc_await { pluginTarget.invoke(
                action: .performCommand(
                    targets: [ target ],
                    arguments: ["veni", "vidi", "vici"]),
                package: package,
                buildEnvironment: BuildEnvironment(platform: .macOS, configuration: .debug),
                scriptRunner: pluginScriptRunner,
                outputDirectory: pluginOutputDir,
                toolSearchDirectories: [UserToolchain.default.swiftCompilerPath.parentDirectory],
                toolNamesToPaths: [:],
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope,
                callbackQueue: delegateQueue,
                delegate: pluginDelegate,
                completion: $0) }
            
            // Check the results.
            let outputText = String(decoding: pluginDelegate.outputData, as: UTF8.self)
            XCTAssertTrue(outputText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("This is MyCommandPlugin."), outputText)
            XCTAssertTrue(outputText.trimmingCharacters(in: .whitespacesAndNewlines).contains("/swiftc"), outputText)
        }
    }
}
