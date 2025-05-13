//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct ArgumentParser.Argument
import protocol ArgumentParser.AsyncParsableCommand
import struct ArgumentParser.CommandConfiguration
import struct ArgumentParser.OptionGroup
import protocol ArgumentParser.ParsableArguments

import struct Basics.AbsolutePath
import var Basics.localFileSystem
import struct Basics.SwiftVersion

import struct CoreCommands.LoggingOptions

import struct SwiftFixIt.SwiftFixIt

private struct Options: ParsableArguments {
    @OptionGroup(title: "Logging")
    var logging: LoggingOptions

    @Argument(
        help: "",
        completion: .file(extensions: [".dia"])
    )
    var diagnosticFiles: [AbsolutePath] = []
}

/// Deserializes `.dia` files and applies all fix-its in place.
package struct SwiftFixitCommand: AsyncParsableCommand {
    package static var configuration = CommandConfiguration(
        commandName: "fixit",
        _superCommandName: "swift",
        abstract: "Deserialize diagnostics and apply fix-its",
        version: SwiftVersion.current.completeDisplayString,
        helpNames: [
            .short,
            .long,
            .customLong("help", withSingleDash: true),
        ]
    )

    @OptionGroup
    fileprivate var options: Options

    package init() {}

    package func run() async throws {
        if self.options.diagnosticFiles.isEmpty {
            return
        }

        let swiftFixIt = try SwiftFixIt(diagnosticFiles: options.diagnosticFiles, fileSystem: localFileSystem)

        try swiftFixIt.applyFixIts()
    }
}
