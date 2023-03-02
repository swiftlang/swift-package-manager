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
import CoreCommands
import TSCBasic

/// A protocol for functions and properties common to all destination subcommands.
protocol DestinationCommand: ParsableCommand {
    /// Common locations options provided by ArgumentParser.
    var locations: LocationOptions { get }
}

extension DestinationCommand {
    /// The file system used by default by this command.
    var fileSystem: FileSystem { localFileSystem }

    /// Parses destinations directory option if provided or uses the default path for cross-compilation destinations
    /// on the file system. A new directory at this path is created if one doesn't exist already.
    /// - Returns: existing or a newly created directory at the computed location.
    func getOrCreateDestinationsDirectory() throws -> AbsolutePath {
        guard var destinationsDirectory = try fileSystem.getSharedCrossCompilationDestinationsDirectory(
            explicitDirectory: locations.crossCompilationDestinationsDirectory
        ) else {
            let expectedPath = try fileSystem.swiftPMCrossCompilationDestinationsDirectory
            throw StringError(
                "Couldn't find or create a directory where cross-compilation destinations are stored: `\(expectedPath)`"
            )
        }

        if !self.fileSystem.exists(destinationsDirectory) {
            destinationsDirectory = try self.fileSystem.getOrCreateSwiftPMCrossCompilationDestinationsDirectory()
        }

        return destinationsDirectory
    }
}
