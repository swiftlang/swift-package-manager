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

struct ResetConfiguration: ConfigurationCommand {
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

    @Argument(help: "A run-time triple of the destination specified by `destination-id` identifier string.")
    var runTimeTriple: String

    func run(
        buildTimeTriple: Triple,
        runTimeTriple: Triple,
        _ destination: Destination,
        _ configurationStore: DestinationConfigurationStore,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        var configuration = destination.pathsConfiguration
        var shouldResetAll = true
        var resetProperties = [String]()

        if sdkRootPath {
            configuration.sdkRootPath = nil
            shouldResetAll = false
            resetProperties.append(CodingKeys.sdkRootPath.stringValue)
        }

        if swiftResourcesPath {
            configuration.swiftResourcesPath = nil
            shouldResetAll = false
            resetProperties.append(CodingKeys.swiftResourcesPath.stringValue)
        }

        if swiftStaticResourcesPath {
            configuration.swiftResourcesPath = nil
            shouldResetAll = false
            resetProperties.append(CodingKeys.swiftStaticResourcesPath.stringValue)
        }

        if includeSearchPath {
            configuration.includeSearchPaths = nil
            shouldResetAll = false
            resetProperties.append(CodingKeys.includeSearchPath.stringValue)
        }

        if librarySearchPath {
            configuration.librarySearchPaths = nil
            shouldResetAll = false
            resetProperties.append(CodingKeys.librarySearchPath.stringValue)
        }

        if toolsetPath {
            configuration.toolsetPaths = nil
            shouldResetAll = false
            resetProperties.append(CodingKeys.toolsetPath.stringValue)
        }

        if shouldResetAll {
            if try !configurationStore.resetConfiguration(destinationID: destinationID, runTimeTriple: runTimeTriple) {
                observabilityScope.emit(
                    warning: "No configuration for destination \(destinationID)"
                )
            } else {
                observabilityScope.emit(
                    info: """
                    All configuration properties of destination `\(destinationID) for run-time triple \
                    `\(runTimeTriple)` were successfully reset.
                    """
                )
            }
        } else {
            var destination = destination
            destination.pathsConfiguration = configuration
            try configurationStore.updateConfiguration(destinationID: destinationID, destination: destination)

            observabilityScope.emit(
                info: """
                These properties of destination `\(destinationID) for run-time triple \
                `\(runTimeTriple)` were successfully reset: \(resetProperties.joined(separator: ", ")).
                """
            )
        }
    }
}
