//
//  TemplatePluginRunner.swift
//  SwiftPM
//
//  Created by John Bute on 2025-06-11.
//

import ArgumentParser
import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import PackageModel
import Workspace
import SPMBuildCore
import TSCUtility

import Foundation
import PackageGraph
import SPMBuildCore
import XCBuildSupport
import TSCBasic
import SourceControl


struct TemplatePluginRunner {

    static func run(
        plugin: ResolvedModule,
        package: ResolvedPackage,
        packageGraph: ModulesGraph,
        arguments: [String],
        swiftCommandState: SwiftCommandState,
        allowNetworkConnections: [SandboxNetworkPermission] = []
    ) async throws -> Data {
        let pluginTarget = try castToPlugin(plugin)
        let pluginsDir = try pluginDirectory(for: plugin.name, in: swiftCommandState)
        let outputDir = pluginsDir.appending("outputs")
        let pluginScriptRunner = try swiftCommandState.getPluginScriptRunner(customPluginsDir: pluginsDir)

        var writableDirs = [outputDir, package.path]
        var allowedNetworkConnections = allowNetworkConnections

        try requestPluginPermissions(
            from: pluginTarget,
            pluginName: plugin.name,
            packagePath: package.path,
            writableDirectories: &writableDirs,
            allowNetworkConnections: &allowedNetworkConnections,
            state: swiftCommandState
        )

        let readOnlyDirs = writableDirs.contains(where: { package.path.isDescendantOfOrEqual(to: $0) }) ? [] : [package.path]
        let toolSearchDirs = try defaultToolSearchDirectories(using: swiftCommandState)

        let buildParams = try swiftCommandState.toolsBuildParameters
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitBuildSystem: .native,
            traitConfiguration: .init(),
            cacheBuildManifest: false,
            productsBuildParameters: swiftCommandState.productsBuildParameters,
            toolsBuildParameters: buildParams,
            packageGraphLoader: { packageGraph }
        )

        let accessibleTools = try await plugin.preparePluginTools(
            fileSystem: swiftCommandState.fileSystem,
            environment: try swiftCommandState.toolsBuildParameters.buildEnvironment,
            for: try pluginScriptRunner.hostTriple
        ) { name, _ in
            // Build the product referenced by the tool, and add the executable to the tool map. Product dependencies are not supported within a package, so if the tool happens to be from the same package, we instead find the executable that corresponds to the product. There is always one, because of autogeneraxtion of implicit executables with the same name as the target if there isn't an explicit one.
            try await buildSystem.build(subset: .product(name, for: .host))
            if let builtTool = try buildSystem.buildPlan.buildProducts.first(where: {
                $0.product.name == name && $0.buildParameters.destination == .host
            }) {
                return try builtTool.binaryPath
            } else {
                return nil
            }
        }

        let delegate = PluginDelegate(swiftCommandState: swiftCommandState, plugin: pluginTarget, echoOutput: false)

        let workingDir = try swiftCommandState.options.locations.packageDirectory
            ?? swiftCommandState.fileSystem.currentWorkingDirectory
            ?? { throw InternalError("Could not determine working directory") }()

        let _ = try await pluginTarget.invoke(
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
            delegate: delegate
        )

        return delegate.lineBufferedOutput
    }

    private static func castToPlugin(_ plugin: ResolvedModule) throws -> PluginModule {
        guard let pluginTarget = plugin.underlying as? PluginModule else {
            throw InternalError("Expected PluginModule")
        }
        return pluginTarget
    }

    private static func pluginDirectory(for name: String, in state: SwiftCommandState) throws -> Basics.AbsolutePath {
        try state.getActiveWorkspace().location.pluginWorkingDirectory.appending(component: name)
    }

    private static func defaultToolSearchDirectories(using state: SwiftCommandState) throws -> [Basics.AbsolutePath] {
        let toolchainPath = try state.getTargetToolchain().swiftCompilerPath.parentDirectory
        let envPaths = Basics.getEnvSearchPaths(pathString: Environment.current[.path], currentWorkingDirectory: nil)
        return [toolchainPath] + envPaths
    }

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
            let (desc, reason, remedy) = describe(permission)

            if state.outputStream.isTTY {
                state.outputStream.write("Plugin '\(pluginName)' wants permission to \(desc).\nStated reason: “\(reason)”.\nAllow? (yes/no) ".utf8)
                state.outputStream.flush()

                guard readLine()?.lowercased() == "yes" else {
                    throw StringError("Permission denied: \(desc)")
                }
            } else {
                throw StringError("Plugin '\(pluginName)' requires: \(desc).\nReason: “\(reason)”.\nUse \(remedy) to allow.")
            }

            switch permission {
            case .writeToPackageDirectory:
                writableDirectories.append(packagePath)
            case .allowNetworkConnections(let scope, _):
                allowNetworkConnections.append(SandboxNetworkPermission(scope))
            }
        }
    }

    private static func describe(_ permission: PluginPermission) -> (String, String, String) {
        switch permission {
        case .writeToPackageDirectory(let reason):
            return ("write to the package directory", reason, "--allow-writing-to-package-directory")
        case .allowNetworkConnections(let scope, let reason):
            let ports = scope.ports.map(String.init).joined(separator: ", ")
            let desc = scope.ports.isEmpty ? "allow \(scope.label) connections" : "allow \(scope.label) on ports: \(ports)"
            return (desc, reason, "--allow-network-connections")
        }
    }
}

