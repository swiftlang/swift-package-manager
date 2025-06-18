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
import SPMBuildCore
import TSCUtility
import Workspace

import Foundation
import PackageGraph
import SourceControl
import SPMBuildCore
import TSCBasic
import XCBuildSupport

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
            """)
        )
        var initMode: InitPackage.PackageType = .library

        /// Which testing libraries to use (and any related options.)
        @OptionGroup()
        var testLibraryOptions: TestLibraryOptions

        /// A custom name for the package. Defaults to the current directory name.
        @Option(name: .customLong("name"), help: "Provide custom package name.")
        var packageName: String?

        // This command should support creating the supplied --package-path if it isn't created.
        var createPackagePath = true

        /// Name of a template to use for package initialization.
        @Option(
            name: .customLong("template"),
            help: "Name of a template to initialize the package, unspecified if the default template should be used."
        )
        var template: String?

        /// Returns true if a template is specified.
        var useTemplates: Bool { self.templateURL != nil || self.templatePackageID != nil || self.templateDirectory != nil }

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

        /// Predetermined arguments specified by the consumer.
        @Argument(
            help: "Predetermined arguments to pass to the template."
        )
        var args: [String] = []

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename

            if self.useTemplates {
                try await self.runTemplateInit(swiftCommandState: swiftCommandState, packageName: packageName, cwd: cwd)
            } else {
                try self.runPackageInit(swiftCommandState: swiftCommandState, packageName: packageName, cwd: cwd)
            }
        }

        /// Runs the standard package initialization (non-template).
        private func runPackageInit(
            swiftCommandState: SwiftCommandState,
            packageName: String,
            cwd: Basics.AbsolutePath
        ) throws {
            let supportedTestingLibraries = computeSupportedTestingLibraries(
                for: testLibraryOptions,
                initMode: initMode,
                swiftCommandState: swiftCommandState
            )

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

        /// Runs the package initialization using an author-defined template.
        private func runTemplateInit(
            swiftCommandState: SwiftCommandState,
            packageName: String,
            cwd: Basics.AbsolutePath
        ) async throws {
            guard let source = templateSource else {
                throw ValidationError("No template source specified.")
            }

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

            let templateInitType = try await swiftCommandState
                .withTemporaryWorkspace(switchingTo: resolvedTemplatePath) { _, _ in
                    try await self.checkConditions(swiftCommandState)
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

            let supportedTemplateTestingLibraries = computeSupportedTestingLibraries(
                for: testLibraryOptions,
                initMode: templateInitType,
                swiftCommandState: swiftCommandState
            )

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
                destinationPath: cwd,
                installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
            )

            try initTemplatePackage.setupTemplateManifest()

            try await TemplateBuildSupport.build(
                swiftCommandState: swiftCommandState,
                buildOptions: self.buildOptions,
                globalOptions: self.globalOptions,
                cwd: cwd
            )

            let packageGraph = try await swiftCommandState.loadPackageGraph()
            let matchingPlugins = PluginCommand.findPlugins(matching: self.template, in: packageGraph, limitedTo: nil)

            guard let commandPlugin = matchingPlugins.first else {
                guard let template = self.template
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
                    "More than one template was found in the package. Please use `--template` to select from one of the available templates: \(templateNames.joined(separator: ", "))"
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
            let response = try initTemplatePackage.promptUser(tool: toolInfo, arguments: args)

            do {
                let _ = try await TemplatePluginRunner.run(
                    plugin: matchingPlugins[0],
                    package: packageGraph.rootPackages.first!,
                    packageGraph: packageGraph,
                    arguments: response,
                    swiftCommandState: swiftCommandState
                )
            }
        }

        /// Validates the loaded manifest to determine package type.
        private func checkConditions(_ swiftCommandState: SwiftCommandState) async throws -> InitPackage.PackageType {
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
                if let target = targets.first(where: { template == nil || $0.name == template }) {
                    if let options = target.templateInitializationOptions {
                        if case .packageInit(let templateType, _, _) = options {
                            return try .init(from: templateType)
                        }
                    }
                }
            }
            throw InternalError(
                "Could not find \(self.template != nil ? "template \(self.template!)" : "any templates in the package")"
            )
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
