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
                guard let type = templateType else {
                    throw InternalError("Template path must be specified when using the local template type.")
                }

                switch type {
                case .local:

                    guard let templatePath = templateDirectory else {
                        throw InternalError("Template path must be specified when using the local template type.")
                    }

                    /// Get the package initialization type based on templateInitializationOptions and check for if the template called is valid.
                    let templateInitType = try await swiftCommandState.withTemporaryWorkspace(switchingTo: templatePath) { workspace, root in
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
                        initMode: type,
                        templatePath: templatePath,
                        fileSystem: swiftCommandState.fileSystem,
                        packageType: templateInitType,
                        supportedTestingLibraries: supportedTemplateTestingLibraries,
                        destinationPath: cwd,
                        installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration,

                    )
                    try initTemplatePackage.setupTemplateManifest()

                    let buildSystem = try await swiftCommandState.withTemporaryWorkspace(switchingTo: globalOptions.locations.packageDirectory ?? cwd) { workspace, root in

                        try await swiftCommandState.createBuildSystem(
                            explicitProduct: buildOptions.product,
                            traitConfiguration: .init(traitOptions: buildOptions.traits),
                            shouldLinkStaticSwiftStdlib: buildOptions.shouldLinkStaticSwiftStdlib,
                            productsBuildParameters: swiftCommandState.productsBuildParameters,
                            toolsBuildParameters: swiftCommandState.toolsBuildParameters,
                            // command result output goes on stdout
                            // ie "swift build" should output to stdout
                            outputStream: TSCBasic.stdoutStream
                        )

                    }

                    guard let subset = buildOptions.buildSubset(observabilityScope: swiftCommandState.observabilityScope) else {
                        throw ExitCode.failure
                    }

                    let _ = try await swiftCommandState.withTemporaryWorkspace(switchingTo: globalOptions.locations.packageDirectory ?? cwd) { workspace, root in
                        do {
                            try await buildSystem.build(subset: subset)
                        }  catch _ as Diagnostics {
                        throw ExitCode.failure
                    }
                }


                case .git:
                    // Implement or call your Git-based template handler
                    print("TODO: Handle Git template")
                case .registry:
                    // Implement or call your Registry-based template handler
                    print("TODO: Handle Registry template")
                }


                let parsedOptions = try PluginCommand.PluginOptions.parse(["--allow-writing-to-package-directory"])
                try await PluginCommand.run(command: template, options: parsedOptions, arguments: ["--","--experimental-dump-help"], swiftCommandState: swiftCommandState)

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
