//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CrossCompilationDestinationsTool

@main
struct SwiftDestinationTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "experimental-destination",
        _superCommandName: "swift",
        abstract: "Perform operations on Swift cross-compilation destinations.",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [
            ConfigureDestination.self,
            InstallDestination.self,
            ListDestinations.self,
            RemoveDestination.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )
}
