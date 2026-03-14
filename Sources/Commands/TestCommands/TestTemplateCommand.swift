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
import ArgumentParserToolInfo

@_spi(SwiftPMInternal)
import Basics

import _Concurrency

@_spi(SwiftPMInternal)
import CoreCommands

import Dispatch
import Foundation
import PackageGraph
@_spi(PackageRefactor) import SwiftRefactor
@_spi(SwiftPMInternal)
import PackageModel

import SPMBuildCore
import TSCUtility

import func TSCLibc.exit
import Workspace

import class Basics.AsyncProcess
import struct TSCBasic.ByteString
import struct TSCBasic.FileSystemError
import enum TSCBasic.JSON
import var TSCBasic.stdoutStream
import class TSCBasic.SynchronizedQueue
import class TSCBasic.Thread

extension SwiftTestCommand {
    /// Test the various outputs of a template.
    struct Template: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Test the various outputs of a template",
            shouldDisplay: true
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var sharedOptions: SharedOptions

        /// Specify name of the template.
        @Option(help: "Specify name of the template")
        var templateName: String?

        /// Specify the output path of the created templates or JSON file containing predetermined template arguments.
        @Option(
            name: .customLong("output-path"),
            help: "Specify the output path of the created templates.",
            completion: .directory
        )
        var outputDirectory: AbsolutePath

        @OptionGroup(visibility: .hidden)
        var buildOptions: BuildCommandOptions

        /// Specify the branch of the template you want to test.
        @Option(
            name: .customLong("branches"),
            parsing: .upToNextOption,
            help: "Specify the branch of the template you want to test. Format: --branches branch1 branch2",
        )
        var branches: [String] = []

        /// Generates a JSON file containing predetermined template arguments.
        @Flag(
            help: "Generate a JSON file containing predetermined arguments for testing templates, written to the output directory."
        )
        var generateArgsFile: Bool = false

        /// Configuration file defining arguments to use when running the template.
        @Argument(help: "Path to a configuration file containing arguments to pass to the template.")
        var argsFile: AbsolutePath?

        /// Output format for the templates result.
        ///
        /// Can be either `.matrix` (default) or `.json`.
        @Option(help: "Set the output format.")
        var format: ShowTestTemplateOutput = .matrix

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            do {
                let directoryManager = TemplateTestingDirectoryManager(
                    fileSystem: swiftCommandState.fileSystem,
                    observabilityScope: swiftCommandState.observabilityScope
                )
                try directoryManager.createOutputDirectory(
                    outputDirectoryPath: self.outputDirectory,
                    swiftCommandState: swiftCommandState
                )

                let buildSystem = self.globalOptions.build.buildSystem != .native ?
                    self.globalOptions.build.buildSystem :
                    swiftCommandState.options.build.buildSystem

                let resolvedTemplateName: String = if self.templateName == nil {
                    try await self.resolveTemplateNameInPackage(from: cwd, swiftCommandState: swiftCommandState)
                } else {
                    self.templateName!
                }

                let initialPackageType = try await inferPackageType(swiftCommandState: swiftCommandState, from: cwd)

                let templateTesterContext = TemplateTesterContext(
                    swiftCommandState: swiftCommandState, initialPackageType: initialPackageType, cwd: cwd,
                    buildSystem: buildSystem, outputDirectory: outputDirectory,
                    buildCommandOptions: self.buildOptions, format: self.format
                )

                try await TemplateTesterPluginManager(
                    template: resolvedTemplateName,
                    branches: self.branches,
                    generateArgsFile: self.generateArgsFile,
                    templateTesterContext: templateTesterContext,
                    args: self.argsFile
                ).run()
            } catch {
                swiftCommandState.observabilityScope.emit(error)
            }
        }

        /// Infers the package type from a template at the given path.
        private func inferPackageType(
            swiftCommandState: SwiftCommandState,
            from templatePath: Basics.AbsolutePath
        ) async throws -> InitPackage.PackageType {
            try await TemplatePackageInitializer.inferPackageType(
                from: templatePath,
                templateName: self.templateName,
                swiftCommandState: swiftCommandState
            )
        }

        /// Finds the template name from a template path.
        func resolveTemplateNameInPackage(
            from templatePath: Basics.AbsolutePath,
            swiftCommandState: SwiftCommandState
        ) async throws -> String {
            try await swiftCommandState.withTemporaryWorkspace(switchingTo: templatePath) { workspace, root in
                let rootManifests = try await workspace.loadRootManifests(
                    packages: root.packages,
                    observabilityScope: swiftCommandState.observabilityScope
                )

                guard let manifest = rootManifests.values.first else {
                    throw TestTemplateCommandError.invalidManifestInTemplate
                }

                return try self.findTemplateName(from: manifest)
            }
        }

        /// Finds the template name from a manifest.
        private func findTemplateName(from manifest: Manifest) throws -> String {
            let templateTargets = manifest.targets.compactMap { target -> String? in
                if let options = target.templateInitializationOptions,
                   case .packageInit = options
                {
                    return target.name
                }
                return nil
            }

            switch templateTargets.count {
            case 0:
                throw TestTemplateCommandError.noTemplatesInManifest
            case 1:
                return templateTargets[0]
            default:
                throw TestTemplateCommandError.multipleTemplatesFound(templateTargets)
            }
        }
    }
}
