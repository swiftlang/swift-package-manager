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
import struct Basics.AbsolutePath
import CoreCommands
import Workspace

import struct Basics.SwiftVersion

/// Top-level `swift workspace` command surface. Groups workspace-scope
/// operations that operate on the enclosing SwiftPM workspace
/// (`Workspace.swift` + `.swiftpm/configuration/`), separate from the
/// package-scope operations under `swift package`.
public struct SwiftWorkspaceCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "workspace",
        _superCommandName: "swift",
        abstract: "Perform workspace-scope operations on the enclosing SwiftPM workspace.",
        discussion: "SEE ALSO: swift package, swift build, swift run, swift test",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [
            Init.self,
            AddMember.self,
            AddDependency.self,
            ListMembers.self,
            RemoveMember.self,
            DumpWorkspace.self,
            Override.self,
            // Shared with the top-level `swift package` command tree —
            // these subcommands are already workspace-aware, so
            // `swift workspace <sub>` invokes the same struct
            // as `swift package <sub>` rather than duplicating the
            // implementation. `Reset` is included for parity: under a
            // workspace it clears the workspace-root scratch state.
            SwiftPackageCommand.Clean.self,
            SwiftPackageCommand.Reset.self,
            SwiftPackageCommand.Update.self,
            SwiftPackageCommand.Resolve.self,
            SwiftPackageCommand.ShowDependencies.self,
            SwiftPackageCommand.Config.self,
       ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
    )

    @OptionGroup()
    var globalOptions: GlobalOptions

    public init() {}
}

/// File-level helper: locates the enclosing workspace root or throws a
/// user-actionable error mentioning `subcommandDisplayName`. Shared by
/// every `swift package workspace <sub>` subcommand that must be
/// invoked from inside a workspace.
package func requireWorkspaceRoot(
    _ swiftCommandState: SwiftCommandState,
    subcommandDisplayName: String,
) throws -> AbsolutePath {
    let cwd = swiftCommandState.fileSystem.currentWorkingDirectory ?? .root
    guard let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
        from: cwd,
        fileSystem: swiftCommandState.fileSystem,
    ) else {
        throw ValidationError(
            "'\(subcommandDisplayName)' must be invoked inside a SwiftPM workspace (no Workspace.swift found starting from \(cwd.pathString))",
        )
    }
    return workspaceRoot
}


/// Discovers the workspace root from the command's current working
/// directory, throwing a user-actionable error when the command
/// is invoked outside a workspace. Common to all three
/// subcommands.
package func requireWorkspaceRoot(
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
