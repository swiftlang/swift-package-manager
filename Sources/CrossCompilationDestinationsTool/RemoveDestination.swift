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
import PackageModel

import struct TSCBasic.AbsolutePath

public struct RemoveDestination: DestinationCommand {
    public static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: """
        Removes a previously installed destination artifact bundle from the filesystem.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(help: "Name of the destination artifact bundle or ID of the destination to remove from the filesystem.")
    var destinationIDOrBundleName: String

    public init() {}

    func run(
        buildTimeTriple: Triple,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        let destinationsDirectory = try self.getOrCreateDestinationsDirectory()
        let artifactBundleDirectory = destinationsDirectory.appending(component: self.destinationIDOrBundleName)

        let removedBundleDirectory: AbsolutePath
        if fileSystem.exists(artifactBundleDirectory) {
            try fileSystem.removeFileTree(artifactBundleDirectory)

            removedBundleDirectory = artifactBundleDirectory
        } else {
            let bundles = try DestinationBundle.getAllValidBundles(
                destinationsDirectory: destinationsDirectory,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope
            )

            let matchingBundles = bundles.compactMap { bundle in
                bundle.artifacts[destinationIDOrBundleName] != nil ? bundle : nil
            }

            guard !matchingBundles.isEmpty else {
                throw StringError(
                    """
                    Neither a destination artifact bundle with name `\(self.destinationIDOrBundleName)` nor an \
                    artifact with such ID are currently installed. Use `list` subcommand to see all available \
                    destinations.
                    """
                )
            }

            guard matchingBundles.count == 1 else {
                let namesOfBundles = matchingBundles.map { "`\($0.name)`" }.joined(separator: ", ")

                throw StringError(
                    """
                    Multiple bundles contain destinations with ID \(self.destinationIDOrBundleName). Names of these \
                    bundles are: \(namesOfBundles). This will lead to issues when specifying such destination for \
                    building. Delete one of the bundles first by their full name to disambiguate.
                    """
                )
            }

            let matchingBundle = matchingBundles[0]

            // Don't leave an empty bundle and remove the whole thing if it has only a single artifact and that's also
            // matching.
            if matchingBundle.artifacts.count > 1 {
                let otherArtifactIDs = matchingBundle.artifacts.keys
                    .filter { $0 == self.destinationIDOrBundleName }
                    .map { "`\($0)`" }
                    .joined(separator: ", ")

                print(
                    """
                    WARNING: the destination bundle containing artifact with ID \(self.destinationIDOrBundleName) \
                    also contains other artifacts: \(otherArtifactIDs).
                    """
                )

                print("Would you like to remove the whole bundle with all of its destinations? (Yes/No): ")
                guard readLine(strippingNewline: true)?.lowercased() == "yes" else {
                    print("Bundle not removed. Exiting...")
                    return
                }
            }

            try fileSystem.removeFileTree(matchingBundle.path)
            removedBundleDirectory = matchingBundle.path
        }

        print(
            """
            Destination artifact bundle at path `\(removedBundleDirectory)` was successfully removed from the \
            file system.
            """
        )
    }
}
