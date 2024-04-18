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
import PackageModel
import PackageModelSyntax
@_spi(FixItApplier) import SwiftIDEUtils
import SwiftParser
import SwiftSyntax
import TSCBasic
import TSCUtility
import Workspace

extension SwiftPackageCommand {
    struct Add: SwiftCommand {
        package static let configuration = CommandConfiguration(
            abstract: "Add a dependency to the package manifest")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The branch to depend on")
        var branch: String?

        @Option(help: "The minimum version requirement")
        var fromVersion: String?

        @Option(help: "The exact version requirement")
        var exactVersion: String?

        @Option(help: "A specific revision requirement")
        var revision: String?

        // FIXME: range option

        @Argument(help: "The URL or directory of the package to add")
        var url: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspace = try swiftCommandState.getActiveWorkspace()

            guard let packagePath = try swiftCommandState.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            // Load the manifest file
            let fileSystem = workspace.fileSystem
            let manifestPath = packagePath.appending("Package.swift")
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

            let identity = PackageIdentity(url: .init(url))

            // Figure out the version requirement.
            let requirement: PackageDependency.SourceControl.Requirement
            if let branch {
                requirement = .branch(branch)
            } else if let fromVersion {
                requirement = .revision(fromVersion)
            } else if let exactVersion {
                requirement = .exact(try Version(versionString: exactVersion))
            } else {
                throw StringError("must specify one of --branch, --from-version, or --exact-version")
            }

            // Figure out the location of the package.
            let location: PackageDependency.SourceControl.Location
            if let path = try? Basics.AbsolutePath(validating: url) {
                location = .local(path)
            } else {
                location = .remote(.init(url))
            }

            let packageDependency: PackageDependency = .sourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: nil,
                location: location,
                requirement: requirement,
                productFilter: .everything
            )

            let edits = try AddPackageDependency.addPackageDependency(
                packageDependency,
                to: manifestSyntax,
                manifestDirectory: packagePath.parentDirectory
            )

            if edits.isEmpty {
                throw StringError("Unable to add package to manifest file")
            }

            let updatedManifestSource = FixItApplier.apply(edits: edits, to: manifestSyntax)
            try fileSystem.writeFileContents(
                manifestPath,
                string: updatedManifestSource
            )
        }
    }
}
