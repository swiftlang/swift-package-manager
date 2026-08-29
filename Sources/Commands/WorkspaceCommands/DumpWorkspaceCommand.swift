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
import Basics // for JSONEncoder.makeWithDefaults
import class Foundation.JSONEncoder
import CoreCommands
import PackageLoading
import Workspace

extension SwiftWorkspaceCommand {

    /// Prints the parsed `Workspace.swift` manifest as JSON. Read-only
    /// companion to `swift package dump-package`, but scoped to the
    /// workspace manifest rather than a member's `Package.swift`. Emits
    /// the workspace path, tools version, member list (identity +
    /// path), and workspace-level dependencies.
    struct DumpWorkspace: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "dump-workspace",
            abstract: "Print the parsed Workspace.swift as JSON.",
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let workspaceRoot = try requireWorkspaceRoot(
                swiftCommandState,
                subcommandDisplayName: "swift package workspace dump-workspace",
            )
            let manifestLoader = try ManifestLoader(
                toolchain: swiftCommandState.getHostToolchain(),
            )
            let manifest = try await PackageWorkspace.loadWorkspaceManifest(
                at: workspaceRoot,
                manifestLoader: manifestLoader,
                fileSystem: swiftCommandState.fileSystem,
                observabilityScope: swiftCommandState.observabilityScope,
            )
            let encoder = JSONEncoder.makeWithDefaults()
            let data = try encoder.encode(manifest)
            print(String(decoding: data, as: UTF8.self))
        }
    }

}
