//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import PackageModel
import SPMBuildCore
import TSCUtility
import Workspace

import Foundation
import PackageGraph
import SourceControl
import SPMBuildCore
import TSCBasic
import XCBuildSupport

/// A utility that runs a plugin target within the context of a resolved Swift package.
///
/// This is used to perform plugin invocations involved in template initialization scripts—
/// with proper sandboxing, permissions, and build system support.
///
/// The plugin must be part of a resolved package graph, and the invocation is handled
/// asynchronously through SwiftPM’s plugin infrastructure.

enum TemplatePluginRunner {
    /// Runs the given plugin target with the specified arguments and environment context.
    ///
    /// This function performs the following steps:
    /// 1. Validates and prepares plugin metadata and permissions.
    /// 2. Prepares the plugin working directory and toolchain.
    /// 3. Resolves required plugin tools, building any products referenced by the plugin.
    /// 4. Invokes the plugin via the configured script runner with sandboxing.
    ///
    /// - Parameters:
    ///   - plugin: The resolved plugin module to run.
    ///   - package: The resolved package to which the plugin belongs.
    ///   - packageGraph: The complete graph of modules used by the build.
    ///   - arguments: Arguments to pass to the plugin at invocation time.
    ///   - swiftCommandState: The current Swift command state including environment, toolchain, and workspace.
    ///   - allowNetworkConnections: A list of pre-authorized network permissions for the plugin sandbox.
    ///
    /// - Returns: A `Data` value representing the plugin’s buffered stdout output.
    ///
    /// - Throws:
    ///   - `InternalError` if expected components (e.g., plugin module or working directory) are missing.
    ///   - `StringError` if permission is denied by the user or plugin configuration is invalid.
    ///   - Any other error thrown during tool resolution, plugin script execution, or build system creation.
    static func run(
        plugin: ResolvedModule,
        package: ResolvedPackage,
        packageGraph: ModulesGraph,
        buildSystem buildSystemKind: BuildSystemProvider.Kind,
        arguments: [String],
        swiftCommandState: SwiftCommandState,
        allowNetworkConnections: [SandboxNetworkPermission] = [],
        requestPermission: Bool
    ) async throws -> Data {
        let pluginTarget = try castToPlugin(plugin)
        let pluginsDir = try pluginDirectory(for: plugin.name, in: swiftCommandState)
        let outputDir = pluginsDir.appending("outputs")
        let pluginScriptRunner = try swiftCommandState.getPluginScriptRunner(customPluginsDir: pluginsDir)

        var writableDirs = [outputDir, package.path]
        var allowedNetworkConnections = allowNetworkConnections

        if requestPermission {
            try requestPluginPermissions(
                from: pluginTarget,
                pluginName: plugin.name,
                packagePath: package.path,
                writableDirectories: &writableDirs,
                allowNetworkConnections: &allowedNetworkConnections,
                state: swiftCommandState
            )
        }

        let readOnlyDirs = writableDirs
            .contains(where: { package.path.isDescendantOfOrEqual(to: $0) }) ? [] : [package.path]
        let toolSearchDirs = try defaultToolSearchDirectories(using: swiftCommandState)

        let buildParams = try swiftCommandState.toolsBuildParameters
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitBuildSystem: buildSystemKind, // FIXME: This should be based on BuildSystemProvider.
            cacheBuildManifest: false,
            productsBuildParameters: swiftCommandState.productsBuildParameters,
            toolsBuildParameters: buildParams,
            packageGraphLoader: { packageGraph }
        )

        let accessibleTools = try await plugin.preparePluginTools(
            fileSystem: swiftCommandState.fileSystem,
            environment: buildParams.buildEnvironment,
            for: try pluginScriptRunner.hostTriple
        ) { name, path in
            // Build the product referenced by the tool, and add the executable to the tool map. Product dependencies are not supported within a package, so if the tool happens to be from the same package, we instead find the executable that corresponds to the product. There is always one, because of autogeneration of implicit executables with the same name as the target if there isn't an explicit one.
            let buildResult = try await buildSystem.build(subset: .product(name, for: .host), buildOutputs: [.buildPlan])

            if let buildPlan = buildResult.buildPlan {
                if let builtTool = buildPlan.buildProducts.first(where: {
                    $0.product.name == name && $0.buildParameters.destination == .host
                }) {
                    return try builtTool.binaryPath
                } else {
                    return nil
                }
            } else {
                return buildParams.buildPath.appending(path)
            }
        }


        let pluginDelegate = PluginDelegate(swiftCommandState: swiftCommandState, buildSystem: buildSystemKind, plugin: pluginTarget, echoOutput: false)

        let workingDir = try swiftCommandState.options.locations.packageDirectory
            ?? swiftCommandState.fileSystem.currentWorkingDirectory
            ?? { throw InternalError("Could not determine working directory") }()

        let success = try await pluginTarget.invoke(
            action: .performCommand(package: package, arguments: arguments),
            buildEnvironment: buildParams.buildEnvironment,
            scriptRunner: pluginScriptRunner,
            workingDirectory: workingDir,
            outputDirectory: outputDir,
            toolSearchDirectories: toolSearchDirs,
            accessibleTools: accessibleTools,
            writableDirectories: writableDirs,
            readOnlyDirectories: readOnlyDirs,
            allowNetworkConnections: allowedNetworkConnections,
            pkgConfigDirectories: swiftCommandState.options.locations.pkgConfigDirectories,
            sdkRootPath: buildParams.toolchain.sdkRootPath,
            fileSystem: swiftCommandState.fileSystem,
            modulesGraph: packageGraph,
            observabilityScope: swiftCommandState.observabilityScope,
            callbackQueue: DispatchQueue(label: "plugin-invocation"),
            delegate: pluginDelegate
        )
        
        guard success else {
            let stringError = pluginDelegate.diagnostics
                .map { $0.message }
                .joined(separator: "\n")

            throw DefaultPluginScriptRunnerError.invocationFailed(
                error: StringError(stringError),
                command: arguments
            )
        }
        return pluginDelegate.lineBufferedOutput
    }

    /// Safely casts a `ResolvedModule` to a `PluginModule`, or throws if invalid.
    private static func castToPlugin(_ plugin: ResolvedModule) throws -> PluginModule {
        guard let pluginTarget = plugin.underlying as? PluginModule else {
            throw InternalError("Expected PluginModule")
        }
        return pluginTarget
    }

    /// Returns the plugin working directory for the specified plugin name.
    private static func pluginDirectory(for name: String, in state: SwiftCommandState) throws -> Basics.AbsolutePath {
        try state.getActiveWorkspace().location.pluginWorkingDirectory.appending(component: name)
    }

    /// Resolves default tool search directories including the toolchain path and user $PATH.
    private static func defaultToolSearchDirectories(using state: SwiftCommandState) throws -> [Basics.AbsolutePath] {
        let toolchainPath = try state.getTargetToolchain().swiftCompilerPath.parentDirectory
        let envPaths = Basics.getEnvSearchPaths(pathString: Environment.current[.path], currentWorkingDirectory: nil)
        return [toolchainPath] + envPaths
    }

    /// Prompts for and grants plugin permissions as specified in the plugin manifest.
    ///
    /// This supports terminal-based interactive prompts and non-interactive failure modes.
    private static func requestPluginPermissions(
        from plugin: PluginModule,
        pluginName: String,
        packagePath: Basics.AbsolutePath,
        writableDirectories: inout [Basics.AbsolutePath],
        allowNetworkConnections: inout [SandboxNetworkPermission],
        state: SwiftCommandState
    ) throws {
        guard case .command(_, let permissions) = plugin.capability else { return }

        for permission in permissions {
            let (desc, reason, remedy) = self.describe(permission)

            if state.outputStream.isTTY {
                state.outputStream
                    .write(
                        "Plugin '\(pluginName)' wants permission to \(desc).\nStated reason: “\(reason)”.\nAllow? (yes/no) "
                            .utf8
                    )
                state.outputStream.flush()

                guard readLine()?.lowercased() == "yes" else {
                    throw StringError("Permission denied: \(desc)")
                }
            } else {
                throw StringError(
                    "Plugin '\(pluginName)' requires: \(desc).\nReason: “\(reason)”.\nUse \(remedy) to allow."
                )
            }

            switch permission {
            case .writeToPackageDirectory:
                writableDirectories.append(packagePath)
            case .allowNetworkConnections(let scope, _):
                allowNetworkConnections.append(SandboxNetworkPermission(scope))
            }
        }
    }

    /// Describes a plugin permission request with a description, reason, and CLI remedy flag.
    private static func describe(_ permission: PluginPermission) -> (String, String, String) {
        switch permission {
        case .writeToPackageDirectory(let reason):
            return ("write to the package directory", reason, "--allow-writing-to-package-directory")
        case .allowNetworkConnections(let scope, let reason):
            let ports = scope.ports.map(String.init).joined(separator: ", ")
            let desc = scope.ports
                .isEmpty ? "allow \(scope.label) connections" : "allow \(scope.label) on ports: \(ports)"
            return (desc, reason, "--allow-network-connections")
        }
    }
}
