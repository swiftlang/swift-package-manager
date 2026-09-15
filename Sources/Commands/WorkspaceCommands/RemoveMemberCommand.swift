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
import struct PackageModel.WorkspaceManifest

extension SwiftWorkspaceCommand {

    /// Removes an existing member entry from the enclosing workspace's
    /// `Workspace.swift`. Fails when the target isn't currently
    /// declared — mirrors `swift package workspace override remove`
    /// so mistyped paths surface loudly instead of silently no-op'ing.
    /// The on-disk member directory and any `Package.swift` inside it
    /// are left untouched; the CLI's job is limited to the manifest.
    struct RemoveMember: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove-member",
            abstract: "Remove a member from this workspace's Workspace.swift.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The member path (relative to the workspace root).")
        var path: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift package workspace remove-member",
            )
            let manifestPath = workspaceRoot.appending(WorkspaceManifest.filename)
            let fileSystem = swiftCommandState.fileSystem
            let source: String = try fileSystem.readFileContents(manifestPath)
            let editedSource = try WorkspaceManifestSyntax.removeMember(self.path, from: source)
            try fileSystem.writeFileContents(manifestPath, string: editedSource)
        }
    }

}
