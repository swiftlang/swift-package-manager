//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
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
import SwiftParser
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax
import TSCBasic
import TSCUtility
import Workspace

import class PackageModel.Manifest

extension SwiftPackageCommand {
    struct AddDependency: SwiftCommand {
        package static let configuration = CommandConfiguration(
            abstract: "Add a package dependency to the manifest."
        )

        @Argument(help: "The URL or directory of the package to add.")
        var dependency: String

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

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

        @Option(help: "Specify dependency type.")
        var type: DependencyType = .url

        @Option(name: .customLong("filter-manifests"), help: "Filter manifests by name pattern")
        var manifestFilter: [String] = []

        enum DependencyType: String, Codable, CaseIterable, ExpressibleByArgument {
            case url
            case path
            case registry
        }

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspace = try swiftCommandState.getActiveWorkspace()
            guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            switch self.type {
            case .url:
                try self.createSourceControlPackage(
                    packagePath: packagePath,
                    workspace: workspace,
                    url: self.dependency
                )
            case .path:
                try self.createFileSystemPackage(
                    packagePath: packagePath,
                    workspace: workspace,
                    directory: self.dependency
                )
            case .registry:
                try self.createRegistryPackage(
                    packagePath: packagePath,
                    workspace: workspace,
                    id: self.dependency
                )
            }
        }

        private func createSourceControlPackage(
            packagePath: Basics.AbsolutePath,
            workspace: Workspace,
            url: String
        ) throws {
            // Collect all of the possible version requirements.
            var requirements: [PackageDependency.SourceControl.Requirement] = []
            if let exact {
                requirements.append(.exact(exact.description))
            }

            if let branch {
                requirements.append(.branch(branch))
            }

            if let revision {
                requirements.append(.revision(revision))
            }

            if let from {
                requirements.append(.rangeFrom(from.description))
            }

            if let upToNextMinorFrom {
                let range: Range<Version> = .upToNextMinor(from: upToNextMinorFrom)
                requirements.append(
                    .range(
                        lowerBound: range.lowerBound.description,
                        upperBound: range.upperBound.description
                    )
                )
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
            switch firstRequirement {
            case .range(let lowerBound, _), .rangeFrom(let lowerBound):
                requirement = if let to {
                    .range(lowerBound: lowerBound, upperBound: to.description)
                } else {
                    firstRequirement
                }
            default:
                requirement = firstRequirement

                if self.to != nil {
                    throw StringError("--to can only be specified with --from or --up-to-next-minor-from")
                }
            }

            try self.applyEdits(
                packagePath: packagePath,
                workspace: workspace,
                packageDependency: .sourceControl(.init(location: url, requirement: requirement))
            )
        }

        private func createRegistryPackage(
            packagePath: Basics.AbsolutePath,
            workspace: Workspace,
            id: String
        ) throws {
            // Collect all of the possible version requirements.
            var requirements: [PackageDependency.Registry.Requirement] = []
            if let exact {
                requirements.append(.exact(exact.description))
            }

            if let from {
                requirements.append(.rangeFrom(from.description))
            }

            if let upToNextMinorFrom {
                let range: Range<Version> = .upToNextMinor(from: upToNextMinorFrom)
                requirements.append(
                    .range(
                        lowerBound: range.lowerBound.description,
                        upperBound: range.upperBound.description
                    )
                )
            }

            if requirements.count > 1 {
                throw StringError(
                    "must specify at most one of --exact, --from, or --up-to-next-minor-from"
                )
            }

            guard let firstRequirement = requirements.first else {
                throw StringError(
                    "must specify one of --exact, --from, or --up-to-next-minor-from"
                )
            }

            let requirement: PackageDependency.Registry.Requirement
            switch firstRequirement {
            case .range(let lowerBound, _), .rangeFrom(let lowerBound):
                requirement = if let to {
                    .range(lowerBound: lowerBound, upperBound: to.description)
                } else {
                    firstRequirement
                }
            default:
                requirement = firstRequirement

                if self.to != nil {
                    throw StringError("--to can only be specified with --from or --up-to-next-minor-from")
                }
            }

            try self.applyEdits(
                packagePath: packagePath,
                workspace: workspace,
                packageDependency: .registry(.init(identity: id, requirement: requirement))
            )
        }

        private func createFileSystemPackage(
            packagePath: Basics.AbsolutePath,
            workspace: Workspace,
            directory: String
        ) throws {
            try self.applyEdits(
                packagePath: packagePath,
                workspace: workspace,
                packageDependency: .fileSystem(.init(path: directory))
            )
        }

        private func findAllManifests(packagePath: Basics.AbsolutePath, fileSystem: Basics.FileSystem) -> [Basics.AbsolutePath] {
            var manifests: [Basics.AbsolutePath] = []

            // Add standard manifest if it exists
            let standardManifest = packagePath.appending(component: Manifest.filename)
            if fileSystem.isFile(standardManifest) {
                manifests.append(standardManifest)
            }

            // Find version specific manifests
            do {
                let packageContents = try fileSystem.getDirectoryContents(packagePath)
                let regexManifestFile = try! Regex(#"^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift$"#)

                for file in packageContents {
                    if try regexManifestFile.firstMatch(in: file) != nil {
                        manifests.append(packagePath.appending(component: file))
                    }
                }
            } catch {
                // If we cannot read directory, just use standard manifest
            }

            // Filter manifests by name patterns if specified
            if !manifestFilter.isEmpty {
                manifests = manifests.filter { manifestPath in
                    let fileName = manifestPath.basename
                    return manifestFilter.contains { pattern in
                        fileName == pattern
                    }
                }
            }

            return manifests
        }

        private func applyEdits(
            packagePath: Basics.AbsolutePath,
            workspace: Workspace,
            packageDependency: PackageDependency
        ) throws {
            // Load the manifest file
            let fileSystem = workspace.fileSystem
            let packageManifests = findAllManifests(packagePath: packagePath, fileSystem: workspace.fileSystem)

            guard !packageManifests.isEmpty else {
                throw StringError("cannot find package manifest in \(packagePath)")
            }

            var successCount = 0
            var errors: [String] = []

            for manifest in packageManifests {
                do {
                    try applyEditsToSingleManifest(manifestPath: manifest, fileSystem: fileSystem, packageDependency: packageDependency)
                    successCount += 1
                } catch {
                    // For single manifest scenarios, rethrow error
                    if packageManifests.count == 1 {
                        throw error
                    }
                    // For multiple manifests, collect error message
                    let errorMessage = "Failed to update \(manifest.basename)"
                    errors.append(errorMessage)
                }
            }

            if successCount == 0 {
                throw StringError("Failed to update any manifest files:\n" + errors.joined(separator: "\n"))
            } else if !errors.isEmpty {
                print("Successfully updated \(successCount)/\(packageManifests.count) manifest files")
                print("Warnings/Errors occured:\n" + errors.joined(separator: "\n"))
            }
        }

        private func applyEditsToSingleManifest(
            manifestPath: Basics.AbsolutePath,
            fileSystem: FileSystem,
            packageDependency: PackageDependency
        ) throws {
            // Load the manifest file
            let manifestContents: ByteString
            do {
                manifestContents = try fileSystem.readFileContents(manifestPath)
            } catch {
                throw StringError("cannot find package manifest in \(manifestPath)")
            }

            // Parse the manifest.
            let manifestSyntax = manifestContents.withData { data in
                data.withUnsafeBytes { buffer in
                    buffer.withMemoryRebound(to: UInt8.self) { buffer in
                        Parser.parse(source: buffer)
                    }
                }
            }

            let editResult = try AddPackageDependency.textRefactor(
                syntax: manifestSyntax,
                in: .init(dependency: packageDependency)
            )

            try editResult.applyEdits(
                to: fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !self.globalOptions.logging.quiet
            )
        }
    }
}
