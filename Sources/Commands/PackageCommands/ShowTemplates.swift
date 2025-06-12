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
    @Option(name: .customLong("template-url"), help: "The git URL of the template.")
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
        let packagePath: Basics.AbsolutePath
        var shouldDeleteAfter = false

        if let templateURL = self.templateURL {
            // Resolve dependency requirement based on provided options.
            let requirement = try DependencyRequirementResolver(
                exact: exact,
                revision: revision,
                branch: branch,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to
            ).resolve(for: .sourceControl) as? PackageDependency.SourceControl.Requirement

            // Download and resolve the Git-based template.
            let resolver = TemplatePathResolver(
                templateSource: .git,
                templateDirectory: nil,
                templateURL: templateURL,
                sourceControlRequirement: requirement,
                registryRequirement: nil,
                packageIdentity: nil
            )
            packagePath = try await resolver.resolve(swiftCommandState: swiftCommandState)
            shouldDeleteAfter = true

        } else if let packageID = self.templatePackageID {

            let requirement = try DependencyRequirementResolver(
                exact: exact,
                revision: revision,
                branch: branch,
                from: from,
                upToNextMinorFrom: upToNextMinorFrom,
                to: to
            ).resolve(for: .registry) as? PackageDependency.Registry.Requirement

            // Download and resolve the Git-based template.
            let resolver = TemplatePathResolver(
                templateSource: .registry,
                templateDirectory: nil,
                templateURL: nil,
                sourceControlRequirement: nil,
                registryRequirement: requirement,
                packageIdentity: packageID
            )

            packagePath = try await resolver.resolve(swiftCommandState: swiftCommandState)
            shouldDeleteAfter = true
        } else {
            // Use the current working directory.
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("No template URL provided and no current directory")
            }
            packagePath = cwd
        }

        // Clean up downloaded package after execution.
        defer {
            if shouldDeleteAfter {
                try? FileManager.default.removeItem(atPath: packagePath.pathString)
            }
        }

        // Load the package graph.
        let packageGraph = try await swiftCommandState.withTemporaryWorkspace(switchingTo: packagePath) { _, _ in
            try await swiftCommandState.loadPackageGraph()
        }

        let rootPackages = packageGraph.rootPackages.map(\.identity)

        // Extract executable modules marked as templates.
        let templates = packageGraph.allModules.filter(\.underlying.template).map { module -> Template in
            if !rootPackages.contains(module.packageIdentity) {
                return Template(package: module.packageIdentity.description, name: module.name)
            } else {
                return Template(package: String?.none, name: module.name)
            }
        }

        // Display templates in the requested format.
        switch self.format {
        case .flatlist:
            for template in templates.sorted(by: { $0.name < $1.name }) {
                if let package = template.package {
                    print("\(template.name) (\(package))")
                } else {
                    print(template.name)
                }
            }

        case .json:
            let encoder = JSONEncoder()
            let data = try encoder.encode(templates)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        }
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

        public init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "flatlist":
                self = .flatlist
            case "json":
                self = .json
            default:
                return nil
            }
        }

        public var description: String {
            switch self {
            case .flatlist: "flatlist"
            case .json: "json"
            }
        }
    }
}
