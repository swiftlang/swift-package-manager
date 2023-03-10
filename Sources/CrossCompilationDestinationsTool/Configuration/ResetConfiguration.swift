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

struct ResetConfiguration: DestinationCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: """
        Resets configuration properties currently applied to a given destination and run-time triple. If no specific \
        property is specified, all of them are reset for the destination.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Flag(help: "Reset custom configuration for a path to a directory containing the SDK root.")
    var sdkRootPath = false

    @Flag(help: "Reset custom configuration for a path to a directory containing Swift resources for dynamic linking.")
    var swiftResourcesPath = false

    @Flag(help: "Reset custom configuration for a path to a directory containing Swift resources for static linking.")
    var swiftStaticResourcesPath = false

    @Flag(help: "Reset custom configuration for a path to a directory containing headers.")
    var includeSearchPath = false

    @Flag(help: "Reset custom configuration for a path to a directory containing libraries.")
    var librarySearchPath = false

    @Flag(help: "Reset custom configuration for a path to a toolset file.")
    var toolsetPath = false

    @Argument(
        help: """
        An identifier of an already installed destination. Use the `list` subcommand to see all available \
        identifiers.
        """
    )
    var destinationID: String

    @Argument(help: "The run-time triple of the destination to configure.")
    var runTimeTriple: String

    func run(
        buildTimeTriple: Triple,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        let configurationStore = try DestinationConfigurationStore(
            buildTimeTriple: buildTimeTriple,
            destinationsDirectoryPath: destinationsDirectory,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        let triple = try Triple(runTimeTriple)

        guard var destination = try configurationStore.readConfiguration(
            destinationID: destinationID,
            runTimeTriple: triple
        ) else {
            throw DestinationError.destinationNotFound(
                artifactID: destinationID,
                builtTimeTriple: buildTimeTriple,
                runTimeTriple: triple
            )
        }

        var configuration = destination.pathsConfiguration
        var shouldResetAll = true

        if sdkRootPath {
            configuration.sdkRootPath = nil
            shouldResetAll = false
        }

        if swiftResourcesPath {
            configuration.swiftResourcesPath = nil
            shouldResetAll = false
        }

        if swiftStaticResourcesPath {
            configuration.swiftResourcesPath = nil
            shouldResetAll = false
        }

        if includeSearchPath {
            configuration.includeSearchPaths = nil
            shouldResetAll = false
        }

        if librarySearchPath {
            configuration.librarySearchPaths = nil
            shouldResetAll = false
        }

        if toolsetPath {
            configuration.toolsetPaths = nil
            shouldResetAll = false
        }

        if shouldResetAll {
            if try !configurationStore.resetConfiguration(destinationID: destinationID, runTimeTriple: triple) {
                observabilityScope.emit(
                    warning: "No configuration for destination \(destinationID)"
                )
            }
        } else {
            try configurationStore.updateConfiguration(destinationID: destinationID, destination: destination)
        }
    }
}
