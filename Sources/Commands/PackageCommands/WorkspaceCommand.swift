//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import PackageLoading
import PackageModel
import Workspace

extension SwiftPackageCommand {
    /// Grouping for workspace-scope operations. This is a proof-of-
    /// concept subtree; long-term the SwiftPM Workspaces plan may
    /// promote it to a top-level `swift workspace` command.
    struct Workspace: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "workspace",
            abstract: "Perform workspace-scope operations on the enclosing SwiftPM workspace.",
            subcommands: [Override.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )
    }
}

extension SwiftPackageCommand.Workspace {
    /// Manage workspace-level dependency overrides
    /// (`.swiftpm/configuration/workspace-overrides.json`).
    struct Override: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "override",
            abstract: "Manage developer-local dependency overrides for the workspace.",
            subcommands: [Add.self, Remove.self, List.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )
    }
}

extension SwiftPackageCommand.Workspace.Override {
    /// Add or replace a workspace-level dependency override.
    struct Add: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add or replace a workspace-level dependency override.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The identity of the workspace-level dependency to override.")
        var identity: String

        @Option(
            help: "Redirect the dependency to this local filesystem path (relative paths resolve against the workspace root).",
        )
        var path: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            let target: AbsolutePath
            if let absolute = try? AbsolutePath(validating: self.path) {
                target = absolute
            } else {
                let relative = try RelativePath(validating: self.path)
                target = workspaceRoot.appending(relative)
            }
            let override = WorkspaceOverridesJSONParser.Override(
                identity: .plain(self.identity),
                overridingDependency: .fileSystem(
                    identity: .plain(self.identity),
                    nameForTargetDependencyResolutionOnly: nil,
                    path: target,
                    productFilter: .everything,
                    traits: nil,
                ),
            )
            try WorkspaceOverridesManager.add(
                override: override,
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }
    }

    /// Remove a workspace-level dependency override.
    struct Remove: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a workspace-level dependency override.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The identity of the override to remove.")
        var identity: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            try WorkspaceOverridesManager.remove(
                identity: .plain(self.identity),
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
        }
    }

    /// List the current workspace-level dependency overrides.
    struct List: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List active workspace-level dependency overrides.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(swiftCommandState)
            let overridesFile = PackageWorkspace.DefaultLocations.workspaceOverridesFile(
                forRootPackage: workspaceRoot,
            )
            let overrides = try WorkspaceOverridesManager.list(
                overridesFile: overridesFile,
                workspaceRoot: workspaceRoot,
                fileSystem: swiftCommandState.fileSystem,
            )
            if overrides.isEmpty {
                print("(no overrides declared)")
                return
            }
            for override in overrides {
                print("\(override.identity): \(overrideDisplayTarget(override.overridingDependency))")
            }
        }
    }

    /// Discovers the workspace root from the command's current working
    /// directory, throwing a user-actionable error when the command
    /// is invoked outside a workspace. Common to all three
    /// subcommands.
    fileprivate static func requireWorkspaceRoot(
        _ swiftCommandState: SwiftCommandState,
    ) throws -> AbsolutePath {
        let cwd = swiftCommandState.fileSystem.currentWorkingDirectory ?? .root
        guard let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
            from: cwd,
            fileSystem: swiftCommandState.fileSystem,
        ) else {
            throw ValidationError(
                "'swift package workspace override' must be invoked inside a SwiftPM workspace (no Workspace.swift found starting from \(cwd.pathString))",
            )
        }
        return workspaceRoot
    }
}

/// Renders the target of an override for the `list` output. Uses the
/// underlying kind's most user-facing location (file path, URL, or
/// registry identifier) — avoids depending on
/// `PackageDependency.locationString`, which is internal to the
/// Workspace module.
private func overrideDisplayTarget(_ dep: PackageDependency) -> String {
    switch dep {
    case .fileSystem(let fs):
        return fs.path.pathString
    case .sourceControl(let sc):
        switch sc.location {
        case .local(let abs):
            return abs.pathString
        case .remote(let url):
            return url.absoluteString
        }
    case .registry(let reg):
        return reg.identity.description
    case .workspaceMember, .workspaceInherited:
        // Rejected by the parser; unreachable via a valid overrides file.
        return "<workspace-scoped>"
    }
}
