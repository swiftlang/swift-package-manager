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
import SourceControl
import Workspace

extension SwiftPackageCommand {
    struct Edit: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a package in editable mode")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The revision to edit", transform: { Revision(identifier: $0) })
        var revision: Revision?

        @Option(name: .customLong("branch"), help: "The branch to create")
        var checkoutBranch: String?

        @Option(help: "Create or use the checkout at this path")
        var path: AbsolutePath?

        @Argument(help: "The identity of the package to edit")
        var packageIdentity: String

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            try await swiftCommandState.resolve(nil)
            let workspace = try swiftCommandState.getActiveWorkspace()

            // Put the dependency in edit mode.
            await workspace.edit(
                packageIdentity: packageIdentity,
                path: path,
                revision: revision,
                checkoutBranch: checkoutBranch,
                observabilityScope: swiftCommandState.observabilityScope
            )
        }
    }

    struct Unedit: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a package from editable mode")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(name: .customLong("force"),
              help: "Unedit the package even if it has uncommitted and unpushed changes")
        var shouldForceRemove: Bool = false

        @Argument(help: "The identity of the package to unedit")
        var packageIdentity: String

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            try await swiftCommandState.resolve(nil)
            let workspace = try swiftCommandState.getActiveWorkspace()

            try await workspace.unedit(
                packageIdentity: packageIdentity,
                forceRemove: shouldForceRemove,
                root: swiftCommandState.getWorkspaceRoot(),
                observabilityScope: swiftCommandState.observabilityScope
            )
        }
    }
}
