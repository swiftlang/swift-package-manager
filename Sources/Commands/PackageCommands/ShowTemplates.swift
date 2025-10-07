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
import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import TSCUtility
import Workspace
@_spi(PackageRefactor) import SwiftRefactor

/// A Swift command that lists the available executable templates from a package.
///
/// The command can work with either a local package or a remote Git-based package template.
/// It supports version specification and configurable output formats (flat list or JSON).
struct ShowTemplates: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the available executables from this package."
    )

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    /// The Git URL of the template to list executables from.
    ///
    /// If not provided, the command uses the current working directory.
    @Option(name: .customLong("url"), help: "The git URL of the template.")
    var templateURL: String?

    @Option(name: .customLong("package-id"), help: "The package identifier of the template")
    var templatePackageID: String?

    /// Output format for the templates list.
    ///
    /// Can be either `.flatlist` (default) or `.json`.
    @Option(help: "Set the output format.")
    var format: ShowTemplatesMode = .flatlist

    // MARK: - Versioning Options for Remote Git Templates

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

        let sourceResolver = DefaultTemplateSourceResolver(
            cwd: cwd,
            fileSystem: swiftCommandState.fileSystem,
            observabilityScope: swiftCommandState.observabilityScope
        )

        let templateSource = sourceResolver.resolveSource(
            directory: cwd, url: self.templateURL, packageID: self.templatePackageID
        )

        if let source = templateSource {
            do {
                try sourceResolver.validate(
                    templateSource: source,
                    directory: cwd,
                    url: self.templateURL,
                    packageID: self.templatePackageID
                )
                let resolvedPath = try await resolveTemplatePath(using: swiftCommandState, source: source)
                let templates = try await loadTemplates(from: resolvedPath, swiftCommandState: swiftCommandState)
                try await displayTemplates(templates, at: resolvedPath, using: swiftCommandState)
                try cleanupTemplate(
                    source: source,
                    path: resolvedPath,
                    fileSystem: swiftCommandState.fileSystem,
                    observabilityScope: swiftCommandState.observabilityScope
                )
            } catch {
                swiftCommandState.observabilityScope.emit(error)
            }
        }
    }

    private func resolveTemplatePath(
        using swiftCommandState: SwiftCommandState,
        source: InitTemplatePackage.TemplateSource
    ) async throws -> Basics.AbsolutePath {
        let requirementResolver = DependencyRequirementResolver(
            packageIdentity: templatePackageID,
            swiftCommandState: swiftCommandState,
            exact: exact,
            revision: revision,
            branch: branch,
            from: from,
            upToNextMinorFrom: upToNextMinorFrom,
            to: to
        )

        var sourceControlRequirement: SwiftRefactor.PackageDependency.SourceControl.Requirement?
        var registryRequirement: SwiftRefactor.PackageDependency.Registry.Requirement?

        switch source {
        case .local:
            sourceControlRequirement = nil
            registryRequirement = nil
        case .git:
            sourceControlRequirement = try? requirementResolver.resolveSourceControl()
            registryRequirement = nil
        case .registry:
            sourceControlRequirement = nil
            registryRequirement = try? await requirementResolver.resolveRegistry()
        }

        return try await TemplatePathResolver(
            source: source,
            templateDirectory: swiftCommandState.fileSystem.currentWorkingDirectory,
            templateURL: self.templateURL,
            sourceControlRequirement: sourceControlRequirement,
            registryRequirement: registryRequirement,
            packageIdentity: self.templatePackageID,
            swiftCommandState: swiftCommandState
        ).resolve()
    }

    private func loadTemplates(
        from path: AbsolutePath,
        swiftCommandState: SwiftCommandState
    ) async throws -> [Template] {
        let graph = try await swiftCommandState.withTemporaryWorkspace(switchingTo: path) { _, _ in
            try await swiftCommandState.loadPackageGraph()
        }

        let rootPackages = graph.rootPackages.map(\.identity)

        return graph.allModules.filter(\.underlying.template).map {
            Template(
                package: rootPackages.contains($0.packageIdentity) ? nil : $0.packageIdentity.description,
                name: $0.name
            )
        }
    }

    private func getDescription(_ swiftCommandState: SwiftCommandState, template: String) async throws -> String {
        let workspace = try swiftCommandState.getActiveWorkspace()
        let root = try swiftCommandState.getWorkspaceRoot()

        let rootManifests = try await workspace.loadRootManifests(
            packages: root.packages,
            observabilityScope: swiftCommandState.observabilityScope
        )
        guard let rootManifest = rootManifests.values.first else {
            throw InternalError("invalid manifests at \(root.packages)")
        }

        let targets = rootManifest.targets

        if let target = targets.first(where: { $0.name == template }),
           let options = target.templateInitializationOptions,
           case .packageInit(_, _, let description) = options
        {
            return description
        }

        throw InternalError(
            "Could not find template \(template)"
        )
    }

    private func displayTemplates(
        _ templates: [Template],
        at path: AbsolutePath,
        using swiftCommandState: SwiftCommandState
    ) async throws {
        switch self.format {
        case .flatlist:
            for template in templates.sorted(by: { $0.name < $1.name }) {
                let description = try await swiftCommandState.withTemporaryWorkspace(switchingTo: path) { _, _ in
                    try await self.getDescription(swiftCommandState, template: template.name)
                }
                if let package = template.package {
                    print("\(template.name) (\(package)) : \(description)")
                } else {
                    print("\(template.name) : \(description)")
                }
            }

        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(templates)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        }
    }

    private func cleanupTemplate(
        source: InitTemplatePackage.TemplateSource,
        path: AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        try TemplateInitializationDirectoryManager(fileSystem: fileSystem, observabilityScope: observabilityScope)
            .cleanupTemporary(templateSource: source, path: path, temporaryDirectory: nil)
    }

    /// Represents a discovered template.
    struct Template: Codable {
        /// Optional name of the external package, if the template comes from one.
        var package: String?
        /// The name of the executable template.
        var name: String
    }

    /// Output format modes for the `ShowTemplates` command.
    enum ShowTemplatesMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
        /// Output as a simple list of template names.
        case flatlist
        /// Output as a JSON array of template objects.
        case json

        init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "flatlist":
                self = .flatlist
            case "json":
                self = .json
            default:
                return nil
            }
        }

        var description: String {
            switch self {
            case .flatlist: "flatlist"
            case .json: "json"
            }
        }
    }
}
