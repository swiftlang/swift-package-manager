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

public struct DestinationCommand: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "experimental-destination",
        _superCommandName: "package",
        abstract: "Perform operations on Swift cross-compilation destinations.",
        subcommands: [
            ListDestinations.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    public init() {}
}
