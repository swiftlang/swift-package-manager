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
import SourceControl

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
        
        @Option(name: .customLong("template-url"), help: "The git URL of the template.")
        var templateURL: String?
        
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
        
        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }
            
            let packageName = self.packageName ?? cwd.basename
            
            if useTemplates {
                try await runTemplateInit(swiftCommandState: swiftCommandState, packageName: packageName, cwd: cwd)
            } else {
                let supportedTestingLibraries = computeSupportedTestingLibraries(for: testLibraryOptions, initMode: initMode, swiftCommandState: swiftCommandState)
                
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
        
        private func runTemplateInit(swiftCommandState: SwiftCommandState, packageName: String, cwd: Basics.AbsolutePath) async throws {
            
            let resolvedTemplatePath: Basics.AbsolutePath
            var requirement: PackageDependency.SourceControl.Requirement?
            
            switch self.templateType {
            case .git:
                requirement = try DependencyRequirementResolver(
                    exact: self.exact,
                    revision: self.revision,
                    branch: self.branch,
                    from: self.from,
                    upToNextMinorFrom: self.upToNextMinorFrom,
                    to: self.to
                ).resolve()
                
                resolvedTemplatePath = try await TemplatePathResolver(
                    templateType: self.templateType,
                    templateDirectory: self.templateDirectory,
                    templateURL: self.templateURL,
                    requirement: requirement
                ).resolve()
                
            case .local, .registry:
                resolvedTemplatePath = try await TemplatePathResolver(
                    templateType: self.templateType,
                    templateDirectory: self.templateDirectory,
                    templateURL: self.templateURL,
                    requirement: nil
                ).resolve()
                
            case .none:
                throw StringError("Missing template type")
            }
            
            let templateInitType = try await swiftCommandState.withTemporaryWorkspace(switchingTo: resolvedTemplatePath) { workspace, root in
                return try await checkConditions(swiftCommandState)
            }
            
            if templateType == .git {
                try FileManager.default.removeItem(at: resolvedTemplatePath.asURL)
            }
            
            let supportedTemplateTestingLibraries = computeSupportedTestingLibraries(for: testLibraryOptions, initMode: templateInitType, swiftCommandState: swiftCommandState)

            let initTemplatePackage = try InitTemplatePackage(
                name: packageName,
                templateName: template,
                initMode: packageDependency(requirement: requirement, resolvedTemplatePath: resolvedTemplatePath),
                templatePath: resolvedTemplatePath,
                fileSystem: swiftCommandState.fileSystem,
                packageType: templateInitType,
                supportedTestingLibraries: supportedTemplateTestingLibraries,
                destinationPath: cwd,
                installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
            )
            
            try initTemplatePackage.setupTemplateManifest()

            try await TemplateBuildSupport.build(swiftCommandState: swiftCommandState, buildOptions: buildOptions, globalOptions: globalOptions, cwd: cwd)

            let packageGraph = try await swiftCommandState.loadPackageGraph()
            let matchingPlugins = PluginCommand.findPlugins(matching: template, in: packageGraph, limitedTo: nil)
            
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
                    if let target = targets.first(where: { $0.name == template }) {
                        if let options = target.templateInitializationOptions {
                            
                            if case let .packageInit(templateType, _, _) = options {
                                return try .init(from: templateType)
                            }
                        }
                    }
                }
            }
            throw InternalError("Could not find template \(template)")
        }

        private func packageDependency(requirement: PackageDependency.SourceControl.Requirement?, resolvedTemplatePath: Basics.AbsolutePath) throws -> MappablePackageDependency.Kind {
            switch templateType {
            case .local:
                return .fileSystem(name: packageName, path: resolvedTemplatePath.asURL.path)

            case .git:
                guard let url = templateURL else {
                    throw StringError("Missing Git url")
                }

                guard let gitRequirement = requirement else {
                    throw StringError("Missing Git requirement")
                }
                return .sourceControl(name: packageName, location: url, requirement: gitRequirement)

            default:
                throw StringError("Not implemented yet")
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

extension InitTemplatePackage.TemplateType: ExpressibleByArgument {}
