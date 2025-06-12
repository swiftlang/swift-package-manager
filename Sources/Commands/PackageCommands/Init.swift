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
        @Option(name: .customLong("template"), help: "Name of a template to initialize the package.")
        var template: String = ""

        /// Returns true if a template is specified.
        var useTemplates: Bool { !self.template.isEmpty }

        /// The type of template to use: `registry`, `git`, or `local`.
        @Option(name: .customLong("template-type"), help: "Template type: registry, git, local.")
        var templateSource: InitTemplatePackage.TemplateSource?

        /// Path to a local template.
        @Option(name: .customLong("template-path"), help: "Path to the local template.", completion: .directory)
        var templateDirectory: Basics.AbsolutePath?

        /// Git URL of the template.
        @Option(name: .customLong("template-url"), help: "The git URL of the template.")
        var templateURL: String?

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
            let resolvedTemplatePath: Basics.AbsolutePath
            var registryRequirement: PackageDependency.Registry.Requirement?
            var sourceControlRequirement: PackageDependency.SourceControl.Requirement?

            switch self.templateSource {
            case .git:
                sourceControlRequirement = try DependencyRequirementResolver(
                    exact: self.exact,
                    revision: self.revision,
                    branch: self.branch,
                    from: self.from,
                    upToNextMinorFrom: self.upToNextMinorFrom,
                    to: self.to
                ).resolve(for: .sourceControl) as? PackageDependency.SourceControl.Requirement


                resolvedTemplatePath = try await TemplatePathResolver(
                    templateSource: self.templateSource,
                    templateDirectory: self.templateDirectory,
                    templateURL: self.templateURL,
                    sourceControlRequirement: sourceControlRequirement,
                    registryRequirement: nil,
                    packageIdentity: nil
                ).resolve(swiftCommandState: swiftCommandState)

            case .local:
                resolvedTemplatePath = try await TemplatePathResolver(
                    templateSource: self.templateSource,
                    templateDirectory: self.templateDirectory,
                    templateURL: self.templateURL,
                    sourceControlRequirement: nil,
                    registryRequirement: nil,
                    packageIdentity: nil
                ).resolve(swiftCommandState: swiftCommandState)
            case .registry:

                registryRequirement = try DependencyRequirementResolver(
                    exact: self.exact,
                    revision: self.revision,
                    branch: self.branch,
                    from: self.from,
                    upToNextMinorFrom: self.upToNextMinorFrom,
                    to: self.to
                ).resolve(for: .registry) as? PackageDependency.Registry.Requirement

                resolvedTemplatePath = try await TemplatePathResolver(
                    templateSource: self.templateSource,
                    templateDirectory: self.templateDirectory,
                    templateURL: self.templateURL,
                    sourceControlRequirement: nil,
                    registryRequirement: registryRequirement,
                    packageIdentity: templatePackageID
                ).resolve(swiftCommandState: swiftCommandState)
            case .none:
                throw StringError("Missing template type")
            }

            let templateInitType = try await swiftCommandState
                .withTemporaryWorkspace(switchingTo: resolvedTemplatePath) { _, _ in
                    try await self.checkConditions(swiftCommandState)
                }

            // Clean up downloaded package after execution.
            defer {
                if templateSource == .git || templateSource == .registry {
                    try? FileManager.default.removeItem(at: resolvedTemplatePath.asURL)
                }
            }

            let supportedTemplateTestingLibraries = computeSupportedTestingLibraries(
                for: testLibraryOptions,
                initMode: templateInitType,
                swiftCommandState: swiftCommandState
            )

            let initTemplatePackage = try InitTemplatePackage(
                name: packageName,
                templateName: template,
                initMode: packageDependency(sourceControlRequirement: sourceControlRequirement, registryRequirement: registryRequirement, resolvedTemplatePath: resolvedTemplatePath),
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

            let output = try await TemplatePluginRunner.run(
                plugin: matchingPlugins[0],
                package: packageGraph.rootPackages.first!,
                packageGraph: packageGraph,
                arguments: ["--", "--experimental-dump-help"],
                swiftCommandState: swiftCommandState
            )

            let toolInfo = try JSONDecoder().decode(ToolInfoV0.self, from: output)
            let response = try initTemplatePackage.promptUser(tool: toolInfo)
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

            for product in products {
                for targetName in product.targets {
                    if let target = targets.first(where: { $0.name == template }) {
                        if let options = target.templateInitializationOptions {
                            if case .packageInit(let templateType, _, _) = options {
                                return try .init(from: templateType)
                            }
                        }
                    }
                }
            }
            throw InternalError("Could not find template \(self.template)")
        }

        /// Transforms the author's package into the required dependency
        private func packageDependency(
            sourceControlRequirement: PackageDependency.SourceControl.Requirement? = nil,
            registryRequirement: PackageDependency.Registry.Requirement? = nil,
            resolvedTemplatePath: Basics.AbsolutePath
        ) throws -> MappablePackageDependency.Kind {
            switch self.templateSource {
            case .local:
                return .fileSystem(name: self.packageName, path: resolvedTemplatePath.asURL.path)

            case .git:
                guard let url = templateURL else {
                    throw StringError("Missing Git url")
                }

                guard let gitRequirement = sourceControlRequirement else {
                    throw StringError("Missing Git requirement")
                }
                return .sourceControl(name: self.packageName, location: url, requirement: gitRequirement)

            case .registry:

                guard let packageID = templatePackageID else {
                    throw StringError("Missing Package ID")
                }


                guard let packageRegistryRequirement = registryRequirement else {
                    throw StringError("Missing Registry requirement")
                }

                return .registry(id: packageID, requirement: packageRegistryRequirement)

            default:
                throw StringError("Missing template source type")
            }

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

extension InitTemplatePackage.TemplateSource: ExpressibleByArgument {}
