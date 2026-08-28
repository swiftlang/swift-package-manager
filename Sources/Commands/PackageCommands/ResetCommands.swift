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
@_spi(SwiftPMInternal) import CoreCommands
import PackageModel
import Workspace

extension SwiftPackageCommand {
    struct Clean: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete build artifacts.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        /// Accepted for parity with the other workspace-aware commands
        /// (`build`, `test`, `run`, `update`) but has no effect under
        /// a workspace: the shared `<workspace-root>/.build/` is
        /// removed regardless. When set, an info diagnostic makes the
        /// no-op behaviour observable. Outside a workspace, `--package`
        /// surfaces the same `packageSelectorRequiresWorkspace` error
        /// used by the other commands.
        @Option(
            name: .customLong("package"),
            help: "Accepted for parity with other workspace-aware commands. Has no effect for `clean` — the workspace uses a shared build directory.",
        )
        var selectedPackage: PackageIdentity?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let cwd = swiftCommandState.fileSystem.currentWorkingDirectory ?? .root
            let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
                from: cwd,
                fileSystem: swiftCommandState.fileSystem,
            )

            if let selectedPackage = self.selectedPackage {
                guard workspaceRoot != nil else {
                    swiftCommandState.observabilityScope.emit(
                        .packageSelectorRequiresWorkspace(requested: selectedPackage),
                    )
                    throw ExitCode.failure
                }
                // Under a workspace: `--package` is a no-op; announce
                // and continue cleaning the shared `.build/`.
                swiftCommandState.observabilityScope.emit(
                    .packageSelectorHasNoEffectForClean(),
                )
            }

            if let workspaceRoot {
                swiftCommandState.observabilityScope.emit(
                    .cleaningWorkspaceBuildDirectory(path: workspaceRoot.appending(".build")),
                )
            }
            try swiftCommandState.getActiveWorkspace().clean(observabilityScope: swiftCommandState.observabilityScope)
        }
    }

    struct PurgeCache: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Purge the global repository cache.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            try await swiftCommandState.purgeCaches(observabilityScope: swiftCommandState.observabilityScope)
        }
    }

    struct Reset: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reset the complete cache/build directory.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        var inclueAdditionalScratchPathFiles: Bool { false }

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            try await swiftCommandState.getActiveWorkspace().reset(observabilityScope: swiftCommandState.observabilityScope)
        }
    }
}

extension Basics.Diagnostic {
    /// Info-level diagnostic emitted at the start of `swift package
    /// clean` when running under a workspace, announcing which
    /// `<workspace-root>/.build` directory is about to be removed.
    /// Users invoking `clean` from a member subdirectory would
    /// otherwise see an unexplained no-op success — this line makes
    /// the workspace-scoped scratch location observable.
    @_spi(SwiftPMInternal)
    public static func cleaningWorkspaceBuildDirectory(path: AbsolutePath) -> Self {
        .info("cleaning workspace build directory: \(path.pathString)")
    }

    /// Info-level diagnostic emitted when `--package X` is supplied to
    /// `swift package clean` under a workspace. The workspace uses a
    /// single shared `.build/` so per-package restriction is
    /// meaningless. The command still succeeds; users get the hint
    /// once and the shared directory is cleaned.
    @_spi(SwiftPMInternal)
    public static func packageSelectorHasNoEffectForClean() -> Self {
        .info(
            "--package has no effect for 'clean' under a workspace; the workspace uses a shared build directory",
        )
    }
}
