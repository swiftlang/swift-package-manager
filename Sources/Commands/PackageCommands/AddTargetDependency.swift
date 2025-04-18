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
import PackageModel
import PackageModelSyntax
import SwiftParser
import SwiftSyntax
import TSCBasic
import TSCUtility
import Workspace

extension SwiftPackageCommand {
    struct AddTargetDependency: SwiftCommand {
        package static let configuration = CommandConfiguration(
            abstract: "Add a new target dependency to the manifest")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The name of the new dependency")
        var dependencyName: String

        @Argument(help: "The name of the target to update")
        var targetName: String

        @Option(help: "The package in which the dependency resides")
        var package: String?

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

            let dependency: TargetDescription.Dependency
            if let package {
                dependency = .product(name: dependencyName, package: package)
            } else {
                dependency = .target(name: dependencyName, condition: nil)
            }

            let editResult = try PackageModelSyntax.AddTargetDependency.addTargetDependency(
                dependency,
                targetName: targetName,
                to: manifestSyntax
            )

            try editResult.applyEdits(
                to: fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !globalOptions.logging.quiet
            )
        }
    }
}

