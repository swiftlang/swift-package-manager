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

struct ShowConfiguration: DestinationCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: """
        Prints all configuration properties currently applied to a given destination and run-time triple.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

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

        guard let configuration = try configurationStore.readConfiguration(
            destinationID: destinationID,
            runTimeTriple: triple
        )?.pathsConfiguration else {
            throw DestinationError.destinationNotFound(
                artifactID: destinationID,
                builtTimeTriple: buildTimeTriple,
                runTimeTriple: triple
            )
        }

        print(configuration)
    }
}

extension Destination.PathsConfiguration: CustomStringConvertible {
    public var description: String {
        """
        sdkRootPath: \(sdkRootPath.configurationString)
        swiftResourcesPath: \(swiftResourcesPath.configurationString)
        swiftStaticResourcesPath: \(swiftStaticResourcesPath.configurationString)
        includeSearchPaths: \(includeSearchPaths.configurationString)
        librarySearchPaths: \(librarySearchPaths.configurationString)
        toolsetPaths: \(toolsetPaths.configurationString)
        """
    }
}

extension Optional where Wrapped == AbsolutePath {
    fileprivate var configurationString: String {
        self?.pathString ?? "not set"
    }
}

extension Optional where Wrapped == [AbsolutePath] {
    fileprivate var configurationString: String {
        self?.map(\.pathString).description ?? "not set"
    }
}
