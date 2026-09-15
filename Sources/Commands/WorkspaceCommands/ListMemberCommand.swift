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
import Workspace

extension SwiftWorkspaceCommand {

    /// Prints every member declared in the enclosing workspace's
    /// `Workspace.swift`. Output is one path per line, sorted
    /// alphabetically by `WorkspaceManifestSyntax.readMembers`. This
    /// is the read-only companion to the (upcoming) `add-member` /
    /// `remove-member` edit commands.
    struct ListMembers: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "list-members",
            abstract: "List the members declared in this workspace's Workspace.swift.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift package workspace list-members",
            )
            let manifestPath = workspaceRoot.appending(WorkspaceManifest.filename)
            let source: String = try swiftCommandState.fileSystem.readFileContents(manifestPath)
            let members = try WorkspaceManifestSyntax.readMembers(from: source)
            for member in members {
                print(member)
            }
        }
    }
}
