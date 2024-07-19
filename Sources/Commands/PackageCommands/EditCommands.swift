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

extension SwiftPackageCommand {
    struct Edit: SwiftCommand {
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

        @Argument(help: "The name of the package to edit")
        var packageName: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            try swiftCommandState.resolve()
            let workspace = try swiftCommandState.getActiveWorkspace()

            // Put the dependency in edit mode.
            workspace.edit(
                packageName: packageName,
                path: path,
                revision: revision,
                checkoutBranch: checkoutBranch,
                observabilityScope: swiftCommandState.observabilityScope
            )
        }
    }

    struct Unedit: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a package from editable mode")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(name: .customLong("force"),
              help: "Unedit the package even if it has uncommitted and unpushed changes")
        var shouldForceRemove: Bool = false

        @Argument(help: "The name of the package to unedit")
        var packageName: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            try swiftCommandState.resolve()
            let workspace = try swiftCommandState.getActiveWorkspace()

            try workspace.unedit(
                packageName: packageName,
                forceRemove: shouldForceRemove,
                root: swiftCommandState.getWorkspaceRoot(),
                observabilityScope: swiftCommandState.observabilityScope
            )
        }
    }
}
