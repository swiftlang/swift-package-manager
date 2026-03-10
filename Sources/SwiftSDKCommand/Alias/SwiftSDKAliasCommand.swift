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

struct SwiftSDKAliasCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias",
        _superCommandName: "sdk",
        abstract: "Manage Swift SDK alias configuration.",
        subcommands: [
            SetAliasRemote.self,
            ListAliases.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
    )

    init() {}
}
