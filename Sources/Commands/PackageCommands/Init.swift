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

        /// Which testing libraries to use (and any related options.)
        @OptionGroup(visibility: .hidden)
        var testLibraryOptions: TestLibraryOptions

        @Option(name: .customLong("name"), help: "Provide custom package name.")
        var packageName: String?

        @OptionGroup(visibility: .hidden)
        var buildOptions: BuildCommandOptions

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
            let versionFlags = VersionFlags(
                exact: exact,
                revision: revision,
                branch: branch,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to
            )

            let state = try PackageInitConfiguration(
                swiftCommandState: swiftCommandState,
                name: packageName,
                initMode: initMode,
                testLibraryOptions: testLibraryOptions,
                buildOptions: buildOptions,
                globalOptions: globalOptions,
                validatePackage: validatePackage,
                args: args,
                directory: templateDirectory,
                url: templateURL,
                packageID: templatePackageID,
                versionFlags: versionFlags
            )

            let initializer = try state.makeInitializer()
            try await initializer.run()
        }

        init() {
        }

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


struct PackageInitConfiguration {
    let packageName: String
    let cwd: Basics.AbsolutePath
    let swiftCommandState: SwiftCommandState
    let initMode: String?
    let templateSource: InitTemplatePackage.TemplateSource?
    let testLibraryOptions: TestLibraryOptions
    let buildOptions: BuildCommandOptions?
    let globalOptions: GlobalOptions?
    let validatePackage: Bool?
    let args: [String]
    let versionResolver: DependencyRequirementResolver?
    let directory: Basics.AbsolutePath?
    let url: String?
    let packageID: String?

    init(
        swiftCommandState: SwiftCommandState,
        name: String?,
        initMode: String?,
        testLibraryOptions: TestLibraryOptions,
        buildOptions: BuildCommandOptions,
        globalOptions: GlobalOptions,
        validatePackage: Bool,
        args: [String],
        directory: Basics.AbsolutePath?,
        url: String?,
        packageID: String?,
        versionFlags: VersionFlags
    ) throws {
        guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
            throw InternalError("Could not find the current working directory")
        }

        self.cwd = cwd
        self.packageName = name ?? cwd.basename
        self.swiftCommandState = swiftCommandState
        self.initMode = initMode
        self.testLibraryOptions = testLibraryOptions
        self.buildOptions = buildOptions
        self.globalOptions = globalOptions
        self.validatePackage = validatePackage
        self.args = args
        self.directory = directory
        self.url = url
        self.packageID = packageID

        let sourceResolver = DefaultTemplateSourceResolver()
        self.templateSource = sourceResolver.resolveSource(
            directory: directory,
            url: url,
            packageID: packageID
        )

        if templateSource != nil {
            self.versionResolver = DependencyRequirementResolver(
                exact: versionFlags.exact,
                revision: versionFlags.revision,
                branch: versionFlags.branch,
                from: versionFlags.from,
                upToNextMinorFrom: versionFlags.upToNextMinorFrom,
                to: versionFlags.to
            )
        } else {
            self.versionResolver = nil
        }
    }

    func makeInitializer() throws -> PackageInitializer {
        if let templateSource = templateSource,
           let versionResolver = versionResolver,
           let buildOptions = buildOptions,
           let globalOptions = globalOptions,
           let validatePackage = validatePackage {

            return TemplatePackageInitializer(
                packageName: packageName,
                cwd: cwd,
                templateSource: templateSource,
                templateName: initMode,
                templateDirectory: self.directory,
                templateURL: self.url,
                templatePackageID: self.packageID,
                versionResolver: versionResolver,
                buildOptions: buildOptions,
                globalOptions: globalOptions,
                validatePackage: validatePackage,
                args: args,
                swiftCommandState: swiftCommandState
            )
        } else {
            return StandardPackageInitializer(
                packageName: packageName,
                initMode: initMode,
                testLibraryOptions: testLibraryOptions,
                cwd: cwd,
                swiftCommandState: swiftCommandState
            )
        }
    }
}


public struct VersionFlags {
    let exact: Version?
    let revision: String?
    let branch: String?
    let from: Version?
    let upToNextMinorFrom: Version?
    let to: Version?
}


protocol TemplateSourceResolver {
    func resolveSource(
        directory: Basics.AbsolutePath?,
        url: String?,
        packageID: String?
    ) -> InitTemplatePackage.TemplateSource?
}

public struct DefaultTemplateSourceResolver: TemplateSourceResolver {
    func resolveSource(
        directory: Basics.AbsolutePath?,
        url: String?,
        packageID: String?
    ) -> InitTemplatePackage.TemplateSource? {
        if url != nil { return .git }
        if packageID != nil { return .registry }
        if directory != nil { return .local }
        return nil
    }
}

extension InitPackage.PackageType: ExpressibleByArgument {}
