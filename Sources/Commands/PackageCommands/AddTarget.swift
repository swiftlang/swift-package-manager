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
import SwiftParser
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax
import TSCBasic
import TSCUtility
import Workspace

extension AddPackageTarget.TestHarness: @retroactive ExpressibleByArgument { }

extension SwiftPackageCommand {
    struct AddTarget: AsyncSwiftCommand {
        /// The type of target that can be specified on the command line.
        enum TargetType: String, Codable, ExpressibleByArgument, CaseIterable {
            case library
            case executable
            case test
            case macro
            case binary
        }

        package static let configuration = CommandConfiguration(
            abstract: "Add a new target to the manifest.")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The name of the new target.")
        var name: String

        @Option(help: "The type of target to add.")
        var type: TargetType = .library

        @Option(
            parsing: .upToNextOption,
            help: "A list of target dependency names."
        )
        var dependencies: [String] = []

        @Option(help: "The URL for a remote binary target.")
        var url: String?

        @Option(help: "The path to a local binary target.")
        var path: String?

        @Option(help: "The checksum for a remote binary target.")
        var checksum: String?

        @Option(help: "The testing library to use when generating test targets, which can be one of 'xctest', 'swift-testing', or 'none'.")
        var testingLibrary: AddPackageTarget.TestHarness = .default

        func run(_ swiftCommandState: SwiftCommandState) async throws {
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

            // Move sources into their own folder if they're directly in `./Sources`.
            try await moveSingleTargetSources(
                workspace: workspace,
                packagePath: packagePath,
                verbose: !globalOptions.logging.quiet,
                observabilityScope: swiftCommandState.observabilityScope
            )

            // Map the target type.
            let type: PackageTarget.TargetKind = switch self.type {
                case .library: .library
                case .executable: .executable
                case .test: .test
                case .macro: .macro
                case .binary: .binary
            }

            // Map dependencies
            let dependencies: [PackageTarget.Dependency] = self.dependencies.map {
                .byName(name: $0)
            }

            let editResult = try AddPackageTarget.manifestRefactor(
                syntax: manifestSyntax,
                in: .init(
                    target: .init(
                        name: name,
                        type: type,
                        dependencies: dependencies,
                        path: path,
                        url: url,
                        checksum: checksum
                    ),
                    testHarness: testingLibrary
                )
            )

            try editResult.applyEdits(
                to: fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !globalOptions.logging.quiet
            )
        }

        // Check if the package has a single target with that target's sources located
        // directly in `./Sources`. If so, move the sources into a folder named after
        // the target before adding a new target.
        private func moveSingleTargetSources(
            workspace: Workspace,
            packagePath: Basics.AbsolutePath,
            verbose: Bool = false,
            observabilityScope: ObservabilityScope
        ) async throws {
            let manifest = try await workspace.loadRootManifest(
                at: packagePath,
                observabilityScope: observabilityScope
            )

            guard let target = manifest.targets.first, manifest.targets.count == 1 else {
                return
            }

            let sourcesFolder = packagePath.appending("Sources")
            let expectedTargetFolder = sourcesFolder.appending(target.name)

            let fileSystem = workspace.fileSystem
            // If there is one target then pull its name out and use that to look for a folder in `Sources/TargetName`.
            // If the folder doesn't exist then we know we have a single target package and we need to migrate files
            // into this folder before we can add a new target.
            if !fileSystem.isDirectory(expectedTargetFolder) {
                if verbose {
                    print(
                        """
                        Moving existing files from \(
                            sourcesFolder.relative(to: packagePath)
                        ) to \(
                            expectedTargetFolder.relative(to: packagePath)
                        )...
                        """,
                        terminator: ""
                    )
                }
                let contentsToMove = try fileSystem.getDirectoryContents(sourcesFolder)
                try fileSystem.createDirectory(expectedTargetFolder)
                for file in contentsToMove {
                    let source = sourcesFolder.appending(file)
                    let destination = expectedTargetFolder.appending(file)
                    try fileSystem.move(from: source, to: destination)
                }
                if verbose {
                    print(" done.")
                }
            }
        }
    }
}

