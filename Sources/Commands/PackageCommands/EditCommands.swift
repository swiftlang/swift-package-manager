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

@_spi(SwiftPMTesting) @_spi(SwiftPMInternal) import CoreCommands
import SourceControl
import Workspace

extension SwiftPackageCommand {
    struct Edit: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a package in editable mode.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The revision to edit.", transform: { Revision(identifier: $0) })
        var revision: Revision?

        @Option(name: .customLong("branch"), help: "The branch to create.")
        var checkoutBranch: String?

        @Option(
            name: [.customLong("checkout-path"), .customLong("path")],
            help: "Create or use the checkout at this path. `--path` is the deprecated spelling — use `--checkout-path`."
        )
        var checkoutPath: AbsolutePath?

        @Argument(help: "The identity of the package to edit.")
        var packageIdentity: String

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            defer {
                let deprecatedArgument = "--path"
                if SwiftCommandState.isArgumentDeprecationWarranted(for: deprecatedArgument, arguments: CommandLine.arguments) {
                    swiftCommandState.observabilityScope.emit(
                        .argumentDeprecated(flag: deprecatedArgument, renamed: "--checkout-path")
                    )
                }
            }

            // `swift package edit` and `unedit` don't have well-
            // defined semantics under a SwiftPM workspace — the
            // workspace owns a shared `.build/` and shared
            // `Package.resolved`, and per-dependency editable
            // checkouts collide with `workspaceMember` / workspace-
            // level dependency declarations. `swift package
            // workspace override` supersedes the "redirect a
            // dependency to a local checkout" use case that `edit`
            // covered in single-package mode.
            if let workspaceRoot = swiftCommandState.workspaceRoot {
                swiftCommandState.observabilityScope.emit(
                    .editUnsupportedUnderWorkspace(workspaceRoot: workspaceRoot),
                )
                throw ExitCode.failure
            }

            try await swiftCommandState.resolve()
            let workspace = try swiftCommandState.getActiveWorkspace()

            // Put the dependency in edit mode.
            await workspace.edit(
                packageIdentity: packageIdentity,
                path: checkoutPath,
                revision: revision,
                checkoutBranch: checkoutBranch,
                observabilityScope: swiftCommandState.observabilityScope
            )

        }
    }

    struct Unedit: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a package from editable mode.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(name: .customLong("force"),
              help: "Unedit the package even if it has uncommitted and unpushed changes.")
        var shouldForceRemove: Bool = false

        @Argument(help: "The identity of the package to unedit.")
        var packageIdentity: String

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            if let workspaceRoot = swiftCommandState.workspaceRoot {
                swiftCommandState.observabilityScope.emit(
                    .uneditUnsupportedUnderWorkspace(workspaceRoot: workspaceRoot),
                )
                throw ExitCode.failure
            }

            try await swiftCommandState.resolve()
            let workspace = try swiftCommandState.getActiveWorkspace()

            try await workspace.unedit(
                packageIdentity: packageIdentity,
                forceRemove: shouldForceRemove,
                root: try await swiftCommandState.getWorkspaceRoot(),
                observabilityScope: swiftCommandState.observabilityScope
            )

            let deprecatedArgument = "--path"
            if SwiftCommandState.isArgumentDeprecationWarranted(for: deprecatedArgument, arguments: CommandLine.arguments) {
                swiftCommandState.observabilityScope.emit(
                    .argumentDeprecated(flag: deprecatedArgument, renamed: "--checkout-path")
                )
            }
        }
    }
}

extension Basics.Diagnostic {
    /// Error emitted when `swift package edit` is invoked under a
    /// SwiftPM workspace. `edit`'s per-dependency editable-checkout
    /// model collides with the workspace's shared `.build/` and
    /// `workspaceMember` / workspace-level `dependencies:`
    /// declarations. Points the user at `swift workspace
    /// override`, which supersedes the "redirect a dependency to a
    /// local checkout" use case for workspaces.
    @_spi(SwiftPMInternal)
    public static func editUnsupportedUnderWorkspace(workspaceRoot: AbsolutePath) -> Self {
        .error(
            """
            swift package edit is not supported under a SwiftPM workspace (rooted at \
            '\(workspaceRoot.pathString)'); use 'swift workspace override' to \
            redirect a dependency to a local checkout instead
            """,
        )
    }

    /// Error emitted when `swift package unedit` is invoked under
    /// a SwiftPM workspace. Same reasoning as
    /// `editUnsupportedUnderWorkspace` — `unedit` is the inverse
    /// of `edit`, and both are subsumed by
    /// `swift workspace override` under a workspace.
    @_spi(SwiftPMInternal)
    public static func uneditUnsupportedUnderWorkspace(workspaceRoot: AbsolutePath) -> Self {
        .error(
            """
            swift package unedit is not supported under a SwiftPM workspace (rooted at \
            '\(workspaceRoot.pathString)'); use 'swift workspace override remove' to \
            drop a dependency redirect instead
            """,
        )
    }
}
