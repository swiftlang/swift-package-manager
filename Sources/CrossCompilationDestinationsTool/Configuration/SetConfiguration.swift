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

struct SetConfiguration: ConfigurationCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: """
        Sets configuration options for installed cross-compilation destinations.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Option(help: "A path to a directory containing the SDK root.")
    var sdkRootPath: String? = nil

    @Option(help: "A path to a directory containing Swift resources for dynamic linking.")
    var swiftResourcesPath: String? = nil

    @Option(help: "A path to a directory containing Swift resources for static linking.")
    var swiftStaticResourcesPath: String? = nil

    @Option(
        parsing: .singleValue,
        help: """
        A path to a directory containing headers. Multiple paths can be specified by providing this option multiple \
        times to the command.
        """
    )
    var includeSearchPath: [String] = []

    @Option(
        parsing: .singleValue,
        help: """
        "A path to a directory containing libraries. Multiple paths can be specified by providing this option multiple \
        times to the command.
        """
    )
    var librarySearchPath: [String] = []

    @Option(
        parsing: .singleValue,
        help: """
        "A path to a toolset file. Multiple paths can be specified by providing this option multiple times to the command.
        """
    )
    var toolsetPath: [String] = []

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
        runTimeTriple: Triple,
        _ destination: Destination,
        _ configurationStore: DestinationConfigurationStore,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        var configuration = destination.pathsConfiguration
        var updatedProperties = [String]()

        let currentWorkingDirectory = fileSystem.currentWorkingDirectory

        if let sdkRootPath {
            configuration.sdkRootPath = try AbsolutePath(validating: sdkRootPath, relativeTo: currentWorkingDirectory)
            updatedProperties.append(CodingKeys.sdkRootPath.stringValue)
        }

        if let swiftResourcesPath {
            configuration.swiftResourcesPath =
                try AbsolutePath(validating: swiftResourcesPath, relativeTo: currentWorkingDirectory)
            updatedProperties.append(CodingKeys.swiftResourcesPath.stringValue)
        }

        if let swiftStaticResourcesPath {
            configuration.swiftResourcesPath =
                try AbsolutePath(validating: swiftStaticResourcesPath, relativeTo: currentWorkingDirectory)
            updatedProperties.append(CodingKeys.swiftStaticResourcesPath.stringValue)
        }

        if !includeSearchPath.isEmpty {
            configuration.includeSearchPaths =
                try includeSearchPath.map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) }
            updatedProperties.append(CodingKeys.includeSearchPath.stringValue)
        }

        if !librarySearchPath.isEmpty {
            configuration.librarySearchPaths =
                try librarySearchPath.map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) }
            updatedProperties.append(CodingKeys.librarySearchPath.stringValue)
        }

        if !toolsetPath.isEmpty {
            configuration.toolsetPaths =
                try toolsetPath.map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) }
            updatedProperties.append(CodingKeys.toolsetPath.stringValue)
        }

        guard !updatedProperties.isEmpty else {
            observabilityScope.emit(
                error: """
                No properties of destination `\(destinationID) for run-time triple `\(runTimeTriple)` were updated \
                since none were specified. Pass `--help` flag to see the list of all available properties.
                """
            )
            return
        }

        var destination = destination
        destination.pathsConfiguration = configuration
        try configurationStore.updateConfiguration(destinationID: destinationID, destination: destination)

        observabilityScope.emit(
            info: """
            These properties of destination `\(destinationID) for run-time triple \
            `\(runTimeTriple)` were successfully updated: \(updatedProperties.joined(separator: ", ")).
            """
        )
    }
}

extension AbsolutePath {
    fileprivate init(validating string: String, relativeTo basePath: AbsolutePath?) throws {
        if let basePath {
            try self.init(validating: string, relativeTo: basePath)
        } else {
            try self.init(validating: string)
        }
    }
}
