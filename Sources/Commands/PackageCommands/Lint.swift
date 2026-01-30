//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import CoreCommands

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lint the package (deprecated).",
        shouldDisplay: false
    )

    // We don't need any arguments because we just want to catch the command itself
    // and fail immediately with the hint.

    func run() throws {
        // Use CleanExit.message to exit cleanly with an error message but without a stack trace
        throw CleanExit.message("error: unknown subcommand 'lint'; did you mean 'swift format lint'?")
    }
}
