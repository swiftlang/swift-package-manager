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
        // FIXME: This test is getting quite long — we should add some support functionality for creating synthetic plugin tests and factor this out into separate tests.
        try testWithTemporaryDirectory { tmpPath in
            // Create a sample package with a library target and a plugin. It depends on a sample package.
            let packageDir = tmpPath.appending(components: "MyPackage")
            try localFileSystem.writeFileContents(packageDir.appending(component: "Package.swift")) {
                $0 <<< """
                // swift-tools-version: 999.0
                import PackageDescription
                let package = Package(
                    name: "MyPackage",
                    dependencies: [
                        .package(name: "HelperPackage", path: "VendoredDependencies/HelperPackage")
                    ],
                    targets: [
                        .target(
                            name: "MyLibrary",
                            dependencies: [
                                .product(name: "HelperLibrary", package: "HelperPackage")
                            ]
                        ),
                        .plugin(
                            name: "PluginPrintingInfo",
                            capability: .command(
                                intent: .custom(verb: "print-info", description: "Description of the command"),
                                permissions: [.writeToPackageDirectory(reason: "Reason for wanting to write to package directory")]
                            )
                        ),
                        .plugin(
                            name: "PluginFailingWithError",
                            capability: .command(
                                intent: .custom(verb: "fail-with-error", description: "Sample plugin that throws an error")
                            )
                        ),
                        .plugin(
                            name: "PluginFailingWithoutError",
                            capability: .command(
                                intent: .custom(verb: "fail-without-error", description: "Sample plugin that exits without error")
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
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "PluginPrintingInfo", "plugin.swift")) {
                $0 <<< """
                    import PackagePlugin
                    
                    @main
                    struct MyCommandPlugin: CommandPlugin {
                        func performCommand(
                            context: PluginContext,
                            targets: [Target],
                            arguments: [String]
                        ) throws {
                            // Check the identity of the root packages.
                            print("Root package is \\(context.package.displayName).")
                    
                            // Check that we can find a tool in the toolchain.
                            let swiftc = try context.tool(named: "swiftc")
                            print("Found the swiftc tool at \\(swiftc.path).")
                        }
                    }
                """
            }
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "PluginFailingWithError", "plugin.swift")) {
                $0 <<< """
                    import PackagePlugin

                    @main
                    struct MyCommandPlugin: CommandPlugin {
                        func performCommand(
                            context: PluginContext,
                            targets: [Target],
                            arguments: [String]
                        ) throws {
                            // Print some output that should appear before the error diagnostic.
                            print("This text should appear before the uncaught thrown error.")

                            // Throw an uncaught error that should be reported as a diagnostics.
                            throw "This is the uncaught thrown error."
                        }
                    }
                    extension String: Error { }
                """
            }
            try localFileSystem.writeFileContents(packageDir.appending(components: "Plugins", "PluginFailingWithoutError", "plugin.swift")) {
                $0 <<< """
                    import PackagePlugin
                    import Foundation

                    @main
                    struct MyCommandPlugin: CommandPlugin {
                        func performCommand(
                            context: PluginContext,
                            targets: [Target],
                            arguments: [String]
                        ) throws {
                            // Print some output that should appear before we exit.
                            print("This text should appear before we exit.")

                            // Just exit with an error code without an emitting error.
                            exit(1)
                        }
                    }
                    extension String: Error { }
                """
            }

            // Create the sample vendored dependency package.
            try localFileSystem.writeFileContents(packageDir.appending(components: "VendoredDependencies", "HelperPackage", "Package.swift")) {
                $0 <<< """
                // swift-tools-version: 5.5
                import PackageDescription
                let package = Package(
                    name: "HelperPackage",
                    products: [
                        .library(
                            name: "HelperLibrary",
                            targets: ["HelperLibrary"]
                        ),
                    ],
                    targets: [
                        .target(
                            name: "HelperLibrary"
                        ),
                    ]
                )
                """
            }
            try localFileSystem.writeFileContents(packageDir.appending(components: "VendoredDependencies", "HelperPackage", "Sources", "HelperLibrary", "library.swift")) {
                $0 <<< """
                    public func Bar() { }
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
            XCTAssert(packageGraph.packages.count == 2, "\(packageGraph.packages)")
            XCTAssert(packageGraph.rootPackages.count == 1, "\(packageGraph.rootPackages)")
            let package = try XCTUnwrap(packageGraph.rootPackages.first)
            
            // Find the regular target in our test package.
            let libraryTarget = try XCTUnwrap(package.targets.map(\.underlyingTarget).first{ $0.name == "MyLibrary" } as? SwiftTarget)
            XCTAssertEqual(libraryTarget.type, .library)
            
            // Set up a delegate to handle callbacks from the command plugin.
            let delegateQueue = DispatchQueue(label: "plugin-invocation")
            class PluginDelegate: PluginInvocationDelegate {
                let delegateQueue: DispatchQueue
                var diagnostics: [Basics.Diagnostic] = []

                init(delegateQueue: DispatchQueue) {
                    self.delegateQueue = delegateQueue
                }
                
                func pluginEmittedOutput(_ data: Data) {
                    // Add each line of emitted output as a `.info` diagnostic.
                    dispatchPrecondition(condition: .onQueue(delegateQueue))
                    let textlines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                    print(textlines.map{ "[TEXT] \($0)" }.joined(separator: "\n"))
                    diagnostics.append(contentsOf: textlines.map{
                        Basics.Diagnostic(severity: .info, message: String($0), metadata: .none)
                    })
                }
                
                func pluginEmittedDiagnostic(_ diagnostic: Basics.Diagnostic) {
                    // Add the diagnostic as-is.
                    dispatchPrecondition(condition: .onQueue(delegateQueue))
                    print("[DIAG] \(diagnostic)")
                    diagnostics.append(diagnostic)
                }
            }

            // Helper function to invoke a plugin with given input and to check its outputs.
            func testCommand(
                package: ResolvedPackage,
                plugin pluginName: String,
                targets targetNames: [String],
                arguments: [String],
                toolSearchDirectories: [AbsolutePath] = [UserToolchain.default.swiftCompilerPath.parentDirectory],
                toolNamesToPaths: [String: AbsolutePath] = [:],
                file: StaticString = #file,
                line: UInt = #line,
                expectFailure: Bool = false,
                diagnosticsChecker: (DiagnosticsTestResult) throws -> Void
            ) {
                // Find the named plugin.
                let plugins = package.targets.compactMap{ $0.underlyingTarget as? PluginTarget }
                guard let plugin = plugins.first(where: { $0.name == pluginName }) else {
                    return XCTFail("There is no plugin target named ‘\(pluginName)’")
                }
                XCTAssertTrue(plugin.type == .plugin, "Target \(plugin) isn’t a plugin")

                // Find the named input targets to the plugin.
                var targets: [ResolvedTarget] = []
                for targetName in targetNames {
                    guard let target = package.targets.first(where: { $0.underlyingTarget.name == targetName }) else {
                        return XCTFail("There is no target named ‘\(targetName)’")
                    }
                    XCTAssertTrue(target.type != .plugin, "Target \(target) is a plugin")
                    targets.append(target)
                }

                let pluginDir = tmpPath.appending(components: package.identity.description, plugin.name)
                let scriptRunner = DefaultPluginScriptRunner(cacheDir: pluginDir.appending(component: "cache"), toolchain: ToolchainConfiguration.default)
                let delegate = PluginDelegate(delegateQueue: delegateQueue)
                do {
                    let success = try tsc_await { plugin.invoke(
                        action: .performCommand(targets: targets, arguments: arguments),
                        package: package,
                        buildEnvironment: BuildEnvironment(platform: .macOS, configuration: .debug),
                        scriptRunner: scriptRunner,
                        outputDirectory: pluginDir.appending(component: "output"),
                        toolSearchDirectories: [UserToolchain.default.swiftCompilerPath.parentDirectory],
                        toolNamesToPaths: [:],
                        writableDirectories: [pluginDir.appending(component: "output")],
                        fileSystem: localFileSystem,
                        observabilityScope: observability.topScope,
                        callbackQueue: delegateQueue,
                        delegate: delegate,
                        completion: $0) }
                    if expectFailure {
                        XCTAssertFalse(success, "expected command to fail, but it succeeded", file: file, line: line)
                    }
                    else {
                        XCTAssertTrue(success, "expected command to succeed, but it failed", file: file, line: line)
                    }
                }
                catch {
                    XCTFail("error \(String(describing: error))", file: file, line: line)
                }
                testDiagnostics(delegate.diagnostics, problemsOnly: false, file: file, line: line, handler: diagnosticsChecker)
            }

            // Invoke the command plugin that prints out various things it was given, and check them.
            testCommand(package: package, plugin: "PluginPrintingInfo", targets: ["MyLibrary"], arguments: ["veni", "vidi", "vici"]) { output in
                output.check(diagnostic: .equal("Root package is MyPackage."), severity: .info)
                output.check(diagnostic: .and(.prefix("Found the swiftc tool"), .suffix(".")), severity: .info)
            }

            // Invoke the command plugin that throws an unhandled error at the top level.
            testCommand(package: package, plugin: "PluginFailingWithError", targets: [], arguments: [], expectFailure: true) { output in
                output.check(diagnostic: .equal("This text should appear before the uncaught thrown error."), severity: .info)
                output.check(diagnostic: .equal("This is the uncaught thrown error."), severity: .error)

            }
            // Invoke the command plugin that exits with code 1 without returning an error.
            testCommand(package: package, plugin: "PluginFailingWithoutError", targets: [], arguments: [], expectFailure: true) { output in
                output.check(diagnostic: .equal("This text should appear before we exit."), severity: .info)
                output.check(diagnostic: .equal("Plugin ended with exit code 1"), severity: .error)
            }
        }
    }
}
