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
import CoreCommands

struct RemoveDestination: DestinationCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: """
        Removes a previously installed destination artifact bundle from the filesystem.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(help: "Name of the destination artifact bundle to remove from the filesystem.")
    var bundleName: String

    func run() throws {
        let destinationsDirectory = try self.getOrCreateDestinationsDirectory()
        let artifactBundleDirectory = destinationsDirectory.appending(component: self.bundleName)

        guard fileSystem.exists(artifactBundleDirectory) else {
            throw StringError(
                """
                Destination artifact bundle with name `\(self.bundleName)` is not currently installed, so \
                it can't be removed.
                """
            )
        }

        try fileSystem.removeFileTree(artifactBundleDirectory)

        print(
            """
            Destination artifact bundle at path `\(artifactBundleDirectory)` was successfully removed from the file \
            system.
            """
        )
    }
}
