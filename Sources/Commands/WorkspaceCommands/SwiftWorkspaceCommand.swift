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
import CoreCommands

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
        subcommands: [Init.self, Override.self],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)],
    )

    @OptionGroup()
    var globalOptions: GlobalOptions

    public init() {}
}
