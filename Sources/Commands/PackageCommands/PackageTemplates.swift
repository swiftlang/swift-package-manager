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
import Workspacex
import TSCUtility


extension SwiftPackageCommand {
    struct PackageTemplates: SwiftCommand {
        public static let configuration = CommandConfiguration(
            commandName: "template",
            abstract: "Initialize a new package based on a template."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions
        
        @Option(
            name: .customLong("template-type"),
            help: ArgumentHelp("Package type:", discussion: """
                        - registry  : Use a template from a package registry.
                        - git       : Use a template from a Git repository.
                        - local     : Use a template from a local directory.
                        """))
        var templateType: TemplateType

        @Option(name: .customLong("package-name"), help: "Provide the name for the new package.")
        var packageName: String?

        //package-path provides the consumer's package

        @Option(
            name: .customLong("template-path"),
            help: "Specify the package path to operate on (default current directory). This changes the working directory before any other operation.",
            completion: .directory
        )
        public var templateDirectory: AbsolutePath

        //options for type git
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


        enum TemplateType: String, Codable, CaseIterable, ExpressibleByArgument {
            case local
            case git
            case registry
        }
        

        func run(_ swiftCommandState: SwiftCommandState) throws {

            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }
            
            switch self.templateType {
            case .local:
                try self.generateFromLocalTemplate(
                    packagePath: templateDirectory,
                )
            case .git:
                try self.generateFromGitTemplate()
            case .generateFromRegistryTemplate:
                try self.generateFromRegistryTemplate()
            }

        }
        
        private func generateFromLocalTemplate(
            packagePath: AbsolutePath
        ) throws {
            
            let template = InitTemplatePackage(initMode: templateType, packageName: packageName, templatePath: templateDirectory, fileSystem: swiftCommandState.fileSystem)
        }
        
        
        private func generateFromGitTemplate(
        ) throws {
            
        }
        
        private func generateFromRegistryTemplate(
        ) throws {
            
        }
    }
}


