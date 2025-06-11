//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
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
import PackageModel
import PackageGraph
import Workspace
import TSCUtility
import TSCBasic
import SourceControl

struct ShowTemplates: AsyncSwiftCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the available executables from this package.")

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

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

    @Option(help: "Set the output format.")
    var format: ShowTemplatesMode = .flatlist

    func run(_ swiftCommandState: SwiftCommandState) async throws {

        let packagePath: Basics.AbsolutePath
            var deleteAfter = false

            // Use local current directory or fetch Git package
            if let templateURL = self.templateURL {
                let requirement = try checkRequirements()
                packagePath = try await getPackageFromGit(destination: templateURL, requirement: requirement)
                deleteAfter = true
            } else {
                guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                    throw InternalError("No template URL provided and no current directory")
                }
                packagePath = cwd
            }

            defer {
                if deleteAfter {
                    try? FileManager.default.removeItem(atPath: packagePath.pathString)
                }
            }


        let packageGraph = try await swiftCommandState.withTemporaryWorkspace(switchingTo: packagePath) { workspace, root in
            return try await swiftCommandState.loadPackageGraph()

        }

        let rootPackages = packageGraph.rootPackages.map { $0.identity }

        let templates = packageGraph.allModules.filter({
            $0.underlying.template
        }).map { module -> Template in
            if !rootPackages.contains(module.packageIdentity) {
                return Template(package: module.packageIdentity.description, name: module.name)
            } else {
                return Template(package: Optional<String>.none, name: module.name)
            }
        }

        switch self.format {
        case .flatlist:
            for template in templates.sorted(by: {$0.name < $1.name }) {
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

    struct Template: Codable {
        var package: String?
        var name: String
    }

    enum ShowTemplatesMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
        case flatlist, json

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
            case .flatlist: return "flatlist"
            case .json: return "json"
            }
        }
    }

    func getPackageFromGit(
        destination: String,
        requirement: PackageDependency.SourceControl.Requirement
    ) async throws -> Basics.AbsolutePath {
        let repositoryProvider = GitRepositoryProvider()

        let fetchStandalonePackageByURL = { () async throws -> Basics.AbsolutePath in
            try withTemporaryDirectory(removeTreeOnDeinit: false) { (tempDir: Basics.AbsolutePath) in
                let url = SourceControlURL(destination)
                let repositorySpecifier = RepositorySpecifier(url: url)

                // This is the working clone destination
                let bareCopyPath = tempDir.appending(component: "bare-copy")

                let workingCopyPath = tempDir.appending(component: "working-copy")

                try repositoryProvider.fetch(repository: repositorySpecifier, to: bareCopyPath)

                try FileManager.default.createDirectory(atPath: workingCopyPath.pathString, withIntermediateDirectories: true)

                        // Validate directory (now should exist)
                        guard try repositoryProvider.isValidDirectory(bareCopyPath) else {
                            throw InternalError("Invalid directory at \(workingCopyPath)")
                        }



                let repository = try repositoryProvider.createWorkingCopyFromBare(repository: repositorySpecifier, sourcePath: bareCopyPath, at: workingCopyPath, editable: true)


                try FileManager.default.removeItem(at: bareCopyPath.asURL)

                switch requirement {
                case .range(let versionRange):
                    let tags = try repository.getTags()
                    let versions = tags.compactMap { Version($0) }
                    let filteredVersions = versions.filter { versionRange.contains($0) }
                    guard let latestVersion = filteredVersions.max() else {
                        throw InternalError("No tags found within the specified version range \(versionRange)")
                    }
                    try repository.checkout(tag: latestVersion.description)

                case .exact(let exactVersion):
                    try repository.checkout(tag: exactVersion.description)

                case .branch(let branchName):
                    try repository.checkout(branch: branchName)

                case .revision(let revision):
                    try repository.checkout(revision: .init(identifier: revision))
                }

                return workingCopyPath
            }
        }

        return try await fetchStandalonePackageByURL()
    }


    func checkRequirements() throws -> PackageDependency.SourceControl.Requirement {
        var requirements : [PackageDependency.SourceControl.Requirement] = []

        if let exact {
            requirements.append(.exact(exact))
        }

        if let branch {
            requirements.append(.branch(branch))
        }

        if let revision {
            requirements.append(.revision(revision))
        }

        if let from {
            requirements.append(.range(.upToNextMajor(from: from)))
        }

        if let upToNextMinorFrom {
            requirements.append(.range(.upToNextMinor(from: upToNextMinorFrom)))
        }

        if requirements.count > 1 {
            throw StringError(
                "must specify at most one of --exact, --branch, --revision, --from, or --up-to-next-minor-from"
            )
        }

        guard let firstRequirement = requirements.first else {
            throw StringError(
                "must specify one of --exact, --branch, --revision, --from, or --up-to-next-minor-from"
            )
        }

        let requirement: PackageDependency.SourceControl.Requirement
        if case .range(let range) = firstRequirement {
            if let to {
                requirement = .range(range.lowerBound ..< to)
            } else {
                requirement = .range(range)
            }
        } else {
            requirement = firstRequirement

            if self.to != nil {
                throw StringError("--to can only be specified with --from or --up-to-next-minor-from")
            }
        }
        return requirement

    }

}
