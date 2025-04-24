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
import CoreCommands
import TSCUtility
import Workspace

import struct PackageGraph.TraitConfiguration

extension SwiftPackageCommand {
    struct ResolveOptions: ParsableArguments {
        @Option(help: "The version to resolve at", transform: { Version($0) })
        var version: Version?

        @Option(help: "The branch to resolve at")
        var branch: String?

        @Option(help: "The revision to resolve at")
        var revision: String?

        @Argument(help: "The name of the package to resolve")
        var packageName: String?

        /// Specifies the traits to build.
        @OptionGroup(visibility: .hidden)
        package var traits: TraitOptions
    }

    struct Resolve: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resolve package dependencies")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            // If a package is provided, use that to resolve the dependencies.
            if let packageName = resolveOptions.packageName {
                let workspace = try swiftCommandState.getActiveWorkspace(traitConfiguration: .init(traitOptions: resolveOptions.traits))
                try await workspace.resolve(
                    packageName: packageName,
                    root: swiftCommandState.getWorkspaceRoot(traitConfiguration: .init(traitOptions: resolveOptions.traits)),
                    version: resolveOptions.version,
                    branch: resolveOptions.branch,
                    revision: resolveOptions.revision,
                    observabilityScope: swiftCommandState.observabilityScope
                )
                if swiftCommandState.observabilityScope.errorsReported {
                    throw ExitCode.failure
                }
            } else {
                // Otherwise, run a normal resolve.
                try await swiftCommandState.resolve(.init(traitOptions: resolveOptions.traits))
            }
        }
    }

    struct Fetch: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(shouldDisplay: false)

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            swiftCommandState.observabilityScope.emit(warning: "'fetch' command is deprecated; use 'resolve' instead")

            let resolveCommand = Resolve(globalOptions: _globalOptions, resolveOptions: _resolveOptions)
            try await resolveCommand.run(swiftCommandState)
        }
    }
}
