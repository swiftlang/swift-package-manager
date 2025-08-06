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
import ArgumentParserToolInfo

import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import PackageModel
import Workspace
import SPMBuildCore
import TSCBasic
import TSCUtility
import Foundation
import PackageGraph


extension SwiftPackageCommand {
    struct Init: AsyncSwiftCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Initialize a new package.")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(
            name: .customLong("type"),
            help: ArgumentHelp("Specifies the package type or template.", discussion: """
                library           - A package with a library.
                executable        - A package with an executable.
                tool              - A package with an executable that uses
                                    Swift Argument Parser. Use this template if you
                                    plan to have a rich set of command-line arguments.
                build-tool-plugin - A package that vends a build tool plugin.
                command-plugin    - A package that vends a command plugin.
                macro             - A package that vends a macro.
                empty             - An empty package with a Package.swift manifest.
                custom            - When used with --path, --url, or --package-id,
                                    this resolves to a template from the specified 
                                    package or location.
                """))
        var initMode: String?

        //if --type is mentioned with one of the seven above, then normal initialization
        // if --type is mentioned along with a templateSource, its a template (no matter what)
        // if-type is not mentioned with no templatesoURCE, then defaults to library
        // if --type is not mentioned and templateSource is not nil, then there is only one template in package

        /// Which testing libraries to use (and any related options.)
        @OptionGroup(visibility: .hidden)
        var testLibraryOptions: TestLibraryOptions

        @Option(name: .customLong("name"), help: "Provide custom package name.")
        var packageName: String?

        @OptionGroup(visibility: .hidden)
        var buildOptions: BuildCommandOptions

        /// The type of template to use: `registry`, `git`, or `local`.
        var templateSource: InitTemplatePackage.TemplateSource? {
            if templateDirectory != nil {
                .local
            } else if templateURL != nil {
                .git
            } else if templatePackageID != nil {
                .registry
            } else {
                nil
            }
        }

        /// Path to a local template.
        @Option(name: .customLong("path"), help: "Path to the local template.", completion: .directory)
        var templateDirectory: Basics.AbsolutePath?

        /// Git URL of the template.
        @Option(name: .customLong("url"), help: "The git URL of the template.")
        var templateURL: String?

        /// Package Registry ID of the template.
        @Option(name: .customLong("package-id"), help: "The package identifier of the template")
        var templatePackageID: String?

        // MARK: - Versioning Options for Remote Git Templates and Registry templates

        /// The exact version of the remote package to use.
        @Option(help: "The exact package version to depend on.")
        var exact: Version?

        /// Specific revision to use (for Git templates).
        @Option(help: "The specific package revision to depend on.")
        var revision: String?

        /// Branch name to use (for Git templates).
        @Option(help: "The branch of the package to depend on.")
        var branch: String?

        /// Version to depend on, up to the next major version.
        @Option(help: "The package version to depend on (up to the next major version).")
        var from: Version?

        /// Version to depend on, up to the next minor version.
        @Option(help: "The package version to depend on (up to the next minor version).")
        var upToNextMinorFrom: Version?

        /// Upper bound on the version range (exclusive).
        @Option(help: "Specify upper bound on the package version range (exclusive).")
        var to: Version?

        /// Validation step to build package post generation and run if package is of type executable
        @Flag(name: .customLong("validate-package"), help: "Run 'swift build' after package generation to validate the template.")
        var validatePackage: Bool = false

        /// Predetermined arguments specified by the consumer.
        @Argument(
            help: "Predetermined arguments to pass to the template."
        )
        var args: [String] = []

        // This command should support creating the supplied --package-path if it isn't created.
        var createPackagePath = true

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename

            // Check for template init path
            if let _ = templateSource {
                // When a template source is provided:
                // - If the user gives a known type, it's probably a misuse
                // - If the user gives an unknown value for --type, treat it as the name of the template
                // - If --type is missing entirely, assume the package has a single template
                try await initTemplate(swiftCommandState)
                return
            } else {
                guard let initModeString = self.initMode else {
                    throw ValidationError("Specify a package type using the --type option.")
                }
                guard let knownType = InitPackage.PackageType(rawValue: initModeString) else {
                    throw ValidationError("Package type \(initModeString) not supported")
                }
                // Configure testing libraries
                var supportedTestingLibraries = Set<TestingLibrary>()
                if testLibraryOptions.isExplicitlyEnabled(.xctest, swiftCommandState: swiftCommandState) ||
                    (knownType == .macro && testLibraryOptions.isEnabled(.xctest, swiftCommandState: swiftCommandState)) {
                    supportedTestingLibraries.insert(.xctest)
                }
                if testLibraryOptions.isExplicitlyEnabled(.swiftTesting, swiftCommandState: swiftCommandState) ||
                    (knownType != .macro && testLibraryOptions.isEnabled(.swiftTesting, swiftCommandState: swiftCommandState)) {
                    supportedTestingLibraries.insert(.swiftTesting)
                }

                let initPackage = try InitPackage(
                    name: packageName,
                    packageType: knownType,
                    supportedTestingLibraries: supportedTestingLibraries,
                    destinationPath: cwd,
                    installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,
                    fileSystem: swiftCommandState.fileSystem
                )
                initPackage.progressReporter = { message in print(message) }
                try initPackage.writePackageStructure()


            }

        }


        public func initTemplate(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename

            try await self.runTemplateInit(swiftCommandState: swiftCommandState, packageName: packageName, cwd: cwd)

        }

        /// Runs the package initialization using an author-defined template.
        private func runTemplateInit(
            swiftCommandState: SwiftCommandState,
            packageName: String,
            cwd: Basics.AbsolutePath
        ) async throws {
            guard let source = templateSource else {
                throw ValidationError("No template source specified.")
            }

            let manifest = cwd.appending(component: Manifest.filename)
            guard swiftCommandState.fileSystem.exists(manifest) == false else {
                throw InitError.manifestAlreadyExists
            }


            let contents = try swiftCommandState.fileSystem.getDirectoryContents(cwd)

            guard contents.isEmpty else {
                throw InitError.nonEmptyDirectory(contents)
            }

            let template = initMode
            let requirementResolver = DependencyRequirementResolver(
                exact: exact,
                revision: revision,
                branch: branch,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to
            )

            let registryRequirement: PackageDependency.Registry.Requirement? =
            try? requirementResolver.resolve(for: .registry) as? PackageDependency.Registry.Requirement

            let sourceControlRequirement: PackageDependency.SourceControl.Requirement? =
            try? requirementResolver.resolve(for: .sourceControl) as? PackageDependency.SourceControl.Requirement

            let resolvedTemplatePath = try await TemplatePathResolver(
                source: templateSource,
                templateDirectory: templateDirectory,
                templateURL: templateURL,
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                packageIdentity: templatePackageID,
                swiftCommandState: swiftCommandState
            ).resolve()

            if let dir = templateDirectory, !swiftCommandState.fileSystem.exists(dir) {
                throw ValidationError("The specified template path does not exist: \(dir.pathString)")
            }

            // Use a transitive staging directory for building
            let tempDir = try swiftCommandState.fileSystem.tempDirectory.appending(component: UUID().uuidString)
            let stagingPackagePath = tempDir.appending(component: "generated-package")

            // Use a directory for cleaning dependencies post build
            let cleanUpPath = tempDir.appending(component: "clean-up")

            try swiftCommandState.fileSystem.createDirectory(tempDir)
            defer {
                try? swiftCommandState.fileSystem.removeFileTree(tempDir)
            }

            // Determine the type by loading the resolved template
            let templateInitType = try await swiftCommandState
                .withTemporaryWorkspace(switchingTo: resolvedTemplatePath) { _, _ in
                    try await self.checkConditions(swiftCommandState, template: template)
                }

            // Clean up downloaded package after execution.
            defer {
                if templateSource == .git {
                    try? FileManager.default.removeItem(at: resolvedTemplatePath.asURL)
                } else if templateSource == .registry {
                    let parentDirectoryURL = resolvedTemplatePath.parentDirectory.asURL
                    try? FileManager.default.removeItem(at: parentDirectoryURL)
                }
            }

            let supportedTemplateTestingLibraries: Set<TestingLibrary> = .init()

            let builder = DefaultPackageDependencyBuilder(
                templateSource: source,
                packageName: packageName,
                templateURL: self.templateURL,
                templatePackageID: self.templatePackageID
            )

            let dependencyKind = try builder.makePackageDependency(
                sourceControlRequirement: sourceControlRequirement,
                registryRequirement: registryRequirement,
                resolvedTemplatePath: resolvedTemplatePath
            )

            let initTemplatePackage = try InitTemplatePackage(
                name: packageName,
                initMode: dependencyKind,
                templatePath: resolvedTemplatePath,
                fileSystem: swiftCommandState.fileSystem,
                packageType: templateInitType,
                supportedTestingLibraries: supportedTemplateTestingLibraries,
                destinationPath: stagingPackagePath,
                installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
            )

            try swiftCommandState.fileSystem.createDirectory(stagingPackagePath, recursive: true)

            try initTemplatePackage.setupTemplateManifest()

            // Build once inside the transitive folder
            try await TemplateBuildSupport.build(
                swiftCommandState: swiftCommandState,
                buildOptions: self.buildOptions,
                globalOptions: self.globalOptions,
                cwd: stagingPackagePath,
                transitiveFolder: stagingPackagePath
            )

            let packageGraph = try await swiftCommandState
                .withTemporaryWorkspace(switchingTo: stagingPackagePath) { _, _ in
                    try await swiftCommandState.loadPackageGraph()
                }

            
            let matchingPlugins = PluginCommand.findPlugins(matching: template, in: packageGraph, limitedTo: nil)

            guard let commandPlugin = matchingPlugins.first else {
                guard let template = template
                else { throw ValidationError("No templates were found in \(packageName)") }

                throw ValidationError("No templates were found that match the name \(template)")
            }

            guard matchingPlugins.count == 1 else {
                let templateNames = matchingPlugins.compactMap { module in
                    let plugin = module.underlying as! PluginModule
                    guard case .command(let intent, _) = plugin.capability else { return String?.none }

                    return intent.invocationVerb
                }
                throw ValidationError(
                    "More than one template was found in the package. Please use `--type` along with one of the available templates: \(templateNames.joined(separator: ", "))"
                )
            }

            let output = try await TemplatePluginRunner.run(
                plugin: commandPlugin,
                package: packageGraph.rootPackages.first!,
                packageGraph: packageGraph,
                arguments: ["--", "--experimental-dump-help"],
                swiftCommandState: swiftCommandState
            )

            let toolInfo = try JSONDecoder().decode(ToolInfoV0.self, from: output)
            let cliResponses = try initTemplatePackage.promptUser(command: toolInfo.command, arguments: args)

            for response in cliResponses {
                _ = try await TemplatePluginRunner.run(
                    plugin: matchingPlugins[0],
                    package: packageGraph.rootPackages.first!,
                    packageGraph: packageGraph,
                    arguments: response,
                    swiftCommandState: swiftCommandState
                )
            }

            // Move finalized package to target cwd
            if swiftCommandState.fileSystem.exists(cwd) {
                try swiftCommandState.fileSystem.removeFileTree(cwd)
            }

            try swiftCommandState.fileSystem.copy(from: stagingPackagePath, to: cleanUpPath)

            let _ = try await swiftCommandState
                .withTemporaryWorkspace(switchingTo: cleanUpPath) { _, _ in
                    try swiftCommandState.getActiveWorkspace().clean(observabilityScope: swiftCommandState.observabilityScope)
            }

            try swiftCommandState.fileSystem.copy(from: cleanUpPath, to: cwd)

            // Restore cwd for build
            if validatePackage {
                try await TemplateBuildSupport.build(
                    swiftCommandState: swiftCommandState,
                    buildOptions: self.buildOptions,
                    globalOptions: self.globalOptions,
                    cwd: cwd
                )
            }
        }



        /// Validates the loaded manifest to determine package type.
        private func checkConditions(_ swiftCommandState: SwiftCommandState, template: String?) async throws -> InitPackage.PackageType {
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

            for _ in products {
                if let target: TargetDescription = targets.first(where: { template == nil || $0.name == template }) {
                    if let options = target.templateInitializationOptions {
                        if case .packageInit(let templateType, _, _) = options {
                            return try .init(from: templateType)
                        }
                    }
                }
            }
            throw ValidationError(
                "Could not find \(template != nil ? "template \(template!)" : "any templates in the package")"
            )
        }
        public init() {}

    }
}

extension InitPackage.PackageType {
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

extension InitPackage.PackageType: ExpressibleByArgument {}
