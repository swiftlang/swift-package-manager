//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
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
import Workspace
import SPMBuildCore
import TSCUtility

import Foundation
import PackageGraph
import SPMBuildCore
import XCBuildSupport
import TSCBasic

import ArgumentParserToolInfo

extension SwiftPackageCommand {
    struct Init: AsyncSwiftCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Initialize a new package.",
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup(visibility: .hidden)
        var buildOptions: BuildCommandOptions

        @Option(
            name: .customLong("type"),
            help: ArgumentHelp("Package type:", discussion: """
                library           - A package with a library.
                executable        - A package with an executable.
                tool              - A package with an executable that uses
                                    Swift Argument Parser. Use this template if you
                                    plan to have a rich set of command-line arguments.
                build-tool-plugin - A package that vends a build tool plugin.
                command-plugin    - A package that vends a command plugin.
                macro             - A package that vends a macro.
                empty             - An empty package with a Package.swift manifest.
                """))
        var initMode: InitPackage.PackageType = .library

        /// Which testing libraries to use (and any related options.)
        @OptionGroup()
        var testLibraryOptions: TestLibraryOptions

        @Option(name: .customLong("name"), help: "Provide custom package name.")
        var packageName: String?

        // This command should support creating the supplied --package-path if it isn't created.
        var createPackagePath = true

        @Option(name: .customLong("template"), help: "Name of a template to initialize the package.")
        var template: String = ""
        var useTemplates: Bool { !template.isEmpty }

        @Option(name: .customLong("template-type"), help: "Template type: registry, git, local.")
        var templateType: InitTemplatePackage.TemplateType?

        @Option(name: .customLong("template-path"), help: "Path to the local template.", completion: .directory)
        var templateDirectory: Basics.AbsolutePath?

        // Git-specific options
        @Option(help: "The exact package version to depend on.")
        var exact: Version?

        @Option(help: "The specific package revision to depend on.")
        var revision: String?

        @Option(help: "The branch of the package to depend on.")
        var branch: String?

        @Option(help: "The package version to depend on (up to the next major version).")
        var from: Version?

        @Option(help: "The package version to depend on (up to the next minor version).")
        var upToNextMinorFrom: Version?

        @Option(help: "Specify upper bound on the package version range (exclusive).")
        var to: Version?

        //swift package init --template woof --template-type local --template-path path here

        //first check the path and see if the template woof is actually there
        //if yes, build and get the templateInitializationOptions from it
        // read templateInitializationOptions and parse permissions + type of package to initialize
        // once read, initialize barebones package with what is needed, and add dependency to local template product
        // swift build, then call --experimental-dump-help on the product
        // prompt user
        // run the executable with the command line stuff

        /// Returns the resolved template path for a given template source.
        func resolveTemplatePath() async throws -> Basics.AbsolutePath {
            switch templateType {
            case .local:
                guard let path = templateDirectory else {
                    throw InternalError("Template path must be specified for local templates.")
                }
                return path

            case .git:
                // TODO: Cache logic and smarter hashing
                throw StringError("git-based templates not yet implemented")

            case .registry:
                // TODO: Lookup and download from registry
                throw StringError("Registry-based templates not yet implemented")

            case .none:
                throw InternalError("Missing --template-type for --template")
            }
        }



        //first,
        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename

            // Testing is on by default, with XCTest only enabled explicitly.
            // For macros this is reversed, since we don't support testing
            // macros with Swift Testing yet.
            if useTemplates {
                let resolvedTemplatePath = try await resolveTemplatePath()

                let templateInitType = try await swiftCommandState.withTemporaryWorkspace(switchingTo: resolvedTemplatePath) { workspace, root in
                    return try await checkConditions(swiftCommandState)
                }

                var supportedTemplateTestingLibraries = Set<TestingLibrary>()
                if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
                    (templateInitType == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
                    supportedTemplateTestingLibraries.insert(.xctest)
                }
                if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
                    (templateInitType != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
                    supportedTemplateTestingLibraries.insert(.swiftTesting)
                }

                let initTemplatePackage = try InitTemplatePackage(
                    name: packageName,
                    templateName: template,
                    initMode: templateType ?? .local,
                    templatePath: resolvedTemplatePath,
                    fileSystem: swiftCommandState.fileSystem,
                    packageType: templateInitType,
                    supportedTestingLibraries: supportedTemplateTestingLibraries,
                    destinationPath: cwd,
                    installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
                )

                try initTemplatePackage.setupTemplateManifest()

                // Build system setup
                let buildSystem = try await swiftCommandState.withTemporaryWorkspace(switchingTo: globalOptions.locations.packageDirectory ?? cwd) { _, _ in
                    try await swiftCommandState.createBuildSystem(
                        explicitProduct: buildOptions.product,
                        traitConfiguration: .init(traitOptions: buildOptions.traits),
                        shouldLinkStaticSwiftStdlib: buildOptions.shouldLinkStaticSwiftStdlib,
                        productsBuildParameters: swiftCommandState.productsBuildParameters,
                        toolsBuildParameters: swiftCommandState.toolsBuildParameters,
                        outputStream: TSCBasic.stdoutStream
                    )
                }

                guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
                    throw ExitCode.failure
                }

                try await swiftCommandState.withTemporaryWorkspace(switchingTo: globalOptions.locations.packageDirectory ?? cwd) { _, _ in
                    do {
                        try await buildSystem.build(subset: subset)
                    } catch _ as Diagnostics {
                        throw ExitCode.failure
                    }
                }

                let packageGraph = try await swiftCommandState.loadPackageGraph()
                let matchingPlugins = PluginCommand.findPlugins(matching: template, in: packageGraph, limitedTo: nil)


                
                let output = try await Self.run(
                    plugin: matchingPlugins[0],
                    package: packageGraph.rootPackages.first!,
                    packageGraph: packageGraph,
                    arguments: ["--", "--experimental-dump-help"],
                    swiftCommandState: swiftCommandState
                )

                let toolInfo = try JSONDecoder().decode(ToolInfoV0.self, from: output)
                let response = try initTemplatePackage.promptUser(tool: toolInfo)
                do {

                    let _ = try await Self.run(
                        plugin: matchingPlugins[0],
                        package: packageGraph.rootPackages.first!,
                        packageGraph: packageGraph,
                        arguments: response,
                        swiftCommandState: swiftCommandState,
                        shouldPrint: true
                    )


                }

            } else {

                var supportedTestingLibraries = Set<TestingLibrary>()
                if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
                    (initMode == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
                    supportedTestingLibraries.insert(.xctest)
                }
                if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
                    (initMode != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
                    supportedTestingLibraries.insert(.swiftTesting)
                }


                let initPackage = try InitPackage(
                    name: packageName,
                    packageType: initMode,
                    supportedTestingLibraries: supportedTestingLibraries,
                    destinationPath: cwd,
                    installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,
                    fileSystem: swiftCommandState.fileSystem
                )

                initPackage.progressReporter = { message in
                    print(message)
                }

                try initPackage.writePackageStructure()
            }
        }


    static func run(
        plugin: ResolvedModule,
        package: ResolvedPackage,
        packageGraph: ModulesGraph,
        allowNetworkConnections: [SandboxNetworkPermission] = [],
        arguments: [String],
        swiftCommandState: SwiftCommandState
    ) async throws -> Data {
        let pluginTarget = plugin.underlying as! PluginModule

        // The `plugins` directory is inside the workspace's main data directory, and contains all temporary files related to this plugin in the workspace.
        let pluginsDir = try swiftCommandState.getActiveWorkspace().location.pluginWorkingDirectory
            .appending(component: plugin.name)

        // The `cache` directory is in the plugin’s directory and is where the plugin script runner caches compiled plugin binaries and any other derived information for this plugin.
        let pluginScriptRunner = try swiftCommandState.getPluginScriptRunner(
            customPluginsDir: pluginsDir
        )

        // The `outputs` directory contains subdirectories for each combination of package and command plugin. Each usage of a plugin has an output directory that is writable by the plugin, where it can write additional files, and to which it can configure tools to write their outputs, etc.
        let outputDir = pluginsDir.appending("outputs")

        // Determine the set of directories under which plugins are allowed to write. We always include the output directory.
        var writableDirectories = [outputDir]

        // FIXME: decide whether this permission needs to be explicitly requested by the plugin target, or not
        writableDirectories.append(package.path)

        var allowNetworkConnections = allowNetworkConnections

        // If the plugin requires permissions, we ask the user for approval.
        if case .command(_, let permissions) = pluginTarget.capability {
            try permissions.forEach {
                let permissionString: String
                let reasonString: String
                let remedyOption: String

                switch $0 {
                case .writeToPackageDirectory(let reason):
                    //guard !options.allowWritingToPackageDirectory else { return } // permission already granted
                    permissionString = "write to the package directory"
                    reasonString = reason
                    remedyOption = "--allow-writing-to-package-directory"
                case .allowNetworkConnections(let scope, let reason):
                    guard scope != .none else { return } // no need to prompt
                    //guard options.allowNetworkConnections != .init(scope) else { return } // permission already granted

                    switch scope {
                    case .all, .local:
                        let portsString = scope.ports
                            .isEmpty ? "on all ports" :
                            "on ports: \(scope.ports.map { "\($0)" }.joined(separator: ", "))"
                        permissionString = "allow \(scope.label) network connections \(portsString)"
                    case .docker, .unixDomainSocket:
                        permissionString = "allow \(scope.label) connections"
                    case .none:
                        permissionString = "" // should not be reached
                    }

                    reasonString = reason
                    // FIXME compute the correct reason for the type of network connection
                    remedyOption =
                        "--allow-network-connections 'Network connection is needed'"
                }

                let problem = "Plugin ‘\(plugin.name)’ wants permission to \(permissionString)."
                let reason = "Stated reason: “\(reasonString)”."
                if swiftCommandState.outputStream.isTTY {
                    // We can ask the user directly, so we do so.
                    let query = "Allow this plugin to \(permissionString)?"
                    swiftCommandState.outputStream.write("\(problem)\n\(reason)\n\(query) (yes/no) ".utf8)
                    swiftCommandState.outputStream.flush()
                    let answer = readLine(strippingNewline: true)
                    // Throw an error if we didn't get permission.
                    if answer?.lowercased() != "yes" {
                        throw StringError("Plugin was denied permission to \(permissionString).")
                    }
                } else {
                    // We can't ask the user, so emit an error suggesting passing the flag.
                    let remedy = "Use `\(remedyOption)` to allow this."
                    throw StringError([problem, reason, remedy].joined(separator: "\n"))
                }

                switch $0 {
                case .writeToPackageDirectory:
                    // Otherwise append the directory to the list of allowed ones.
                    writableDirectories.append(package.path)
                case .allowNetworkConnections(let scope, _):
                    allowNetworkConnections.append(.init(scope))
                }
            }
        }

        // Make sure that the package path is read-only unless it's covered by any of the explicitly writable directories.
        let readOnlyDirectories = writableDirectories
            .contains { package.path.isDescendantOfOrEqual(to: $0) } ? [] : [package.path]

        // Use the directory containing the compiler as an additional search directory, and add the $PATH.
        let toolSearchDirs = [try swiftCommandState.getTargetToolchain().swiftCompilerPath.parentDirectory]
            + getEnvSearchPaths(pathString: Environment.current[.path], currentWorkingDirectory: .none)

        let buildParameters = try swiftCommandState.toolsBuildParameters
        // Build or bring up-to-date any executable host-side tools on which this plugin depends. Add them and any binary dependencies to the tool-names-to-path map.
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitBuildSystem: .native,
            traitConfiguration: .init(),
            cacheBuildManifest: false,
            productsBuildParameters: swiftCommandState.productsBuildParameters,
            toolsBuildParameters: buildParameters,
            packageGraphLoader: { packageGraph }
        )

        let accessibleTools = try await plugin.preparePluginTools(
            fileSystem: swiftCommandState.fileSystem,
            environment: buildParameters.buildEnvironment,
            for: try pluginScriptRunner.hostTriple
        ) { name, _ in
            // Build the product referenced by the tool, and add the executable to the tool map. Product dependencies are not supported within a package, so if the tool happens to be from the same package, we instead find the executable that corresponds to the product. There is always one, because of autogeneration of implicit executables with the same name as the target if there isn't an explicit one.
            try await buildSystem.build(subset: .product(name, for: .host))
            if let builtTool = try buildSystem.buildPlan.buildProducts.first(where: {
                $0.product.name == name && $0.buildParameters.destination == .host
            }) {
                return try builtTool.binaryPath
            } else {
                return nil
            }
        }

        // Set up a delegate to handle callbacks from the command plugin.
        let pluginDelegate = PluginDelegate(swiftCommandState: swiftCommandState, plugin: pluginTarget, echoOutput: false)
        let delegateQueue = DispatchQueue(label: "plugin-invocation")

        // Run the command plugin.

        // TODO: use region based isolation when swift 6 is available
        let writableDirectoriesCopy = writableDirectories
        let allowNetworkConnectionsCopy = allowNetworkConnections

        guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
            throw InternalError("Could not find the current working directory")
        }

        guard let workingDirectory = swiftCommandState.options.locations.packageDirectory ?? swiftCommandState.fileSystem.currentWorkingDirectory else {
            throw InternalError("Could not find current working directory")
        }
        let buildEnvironment = buildParameters.buildEnvironment
        try await pluginTarget.invoke(
            action: .performCommand(package: package, arguments: arguments),
            buildEnvironment: buildEnvironment,
            scriptRunner: pluginScriptRunner,
            workingDirectory: workingDirectory,
            outputDirectory: outputDir,
            toolSearchDirectories: toolSearchDirs,
            accessibleTools: accessibleTools,
            writableDirectories: writableDirectoriesCopy,
            readOnlyDirectories: readOnlyDirectories,
            allowNetworkConnections: allowNetworkConnectionsCopy,
            pkgConfigDirectories: swiftCommandState.options.locations.pkgConfigDirectories,
            sdkRootPath: buildParameters.toolchain.sdkRootPath,
            fileSystem: swiftCommandState.fileSystem,
            modulesGraph: packageGraph,
            observabilityScope: swiftCommandState.observabilityScope,
            callbackQueue: delegateQueue,
            delegate: pluginDelegate
        )

        return pluginDelegate.lineBufferedOutput
    }

        // first save current activeWorkspace
        //second switch activeWorkspace to the template Path
        //third revert after conditions have been checked, (we will also get stuff needed for dpeende
        private func checkConditions(_ swiftCommandState: SwiftCommandState) async throws -> InitPackage.PackageType{

            let workspace = try swiftCommandState.getActiveWorkspace()
            let root = try swiftCommandState.getWorkspaceRoot()

            let rootManifests = try await workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: swiftCommandState.observabilityScope
            )
            guard let rootManifest = rootManifests.values.first else {
                throw InternalError("invalid manifests at \(root.packages)")
            }

            let products = rootManifest.products
            let targets = rootManifest.targets

            for product in products {
                for targetName in product.targets {
                    if let target = targets.first(where: { _ in template == targetName }) {
                        if target.type == .template {
                            if let options = target.templateInitializationOptions {

                                if case let .packageInit(templateType, _, _) = options {
                                    return try .init(from: templateType)
                                }
                            }
                        }
                    }
                }
            }
            throw InternalError("Could not find template \(template)")
        }
    }
}

extension InitPackage.PackageType: ExpressibleByArgument {
        init(from templateType: TargetDescription.TemplateType) throws {
            switch templateType {
            case .executable:
                self = .executable
            case .library:
                self = .library
            case .tool:
                self = .tool
            case .macro:
                self = .macro
            case .buildToolPlugin:
                self = .buildToolPlugin
            case .commandPlugin:
                self = .commandPlugin
            case .empty:
                self = .empty
    }
    }

}

extension InitTemplatePackage.TemplateType: ExpressibleByArgument {}
