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
import PackageModel

import struct TSCBasic.AbsolutePath

protocol ConfigurationCommand: DestinationCommand {
    /// An identifier of an already installed destination.
    var destinationID: String { get }

    /// A run-time triple of the destination specified by `destinationID` identifier string.
    var runTimeTriple: String { get }

    /// Run a command related to configuration of cross-compilation destinations, passing it required configuration
    /// values.
    /// - Parameters:
    ///   - buildTimeTriple: triple of the machine this command is running on.
    ///   - runTimeTriple: triple of the machine on which cross-compiled code will run on.
    ///   - destination: destination configuration fetched that matches currently set `destinationID` and
    ///   `runTimeTriple`.
    ///   - configurationStore: storage for configuration properties that this command operates on.
    ///   - destinationsDirectory: directory containing destination artifact bundles and their configuration.
    ///   - observabilityScope: observability scope used for logging.
    func run(
        buildTimeTriple: Triple,
        runTimeTriple: Triple,
        _ destination: Destination,
        _ configurationStore: DestinationConfigurationStore,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws
}

extension ConfigurationCommand {
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
        let runTimeTriple = try Triple(self.runTimeTriple)

        guard let destination = try configurationStore.readConfiguration(
            destinationID: destinationID,
            runTimeTriple: runTimeTriple
        ) else {
            throw DestinationError.destinationNotFound(
                artifactID: destinationID,
                builtTimeTriple: buildTimeTriple,
                runTimeTriple: runTimeTriple
            )
        }

        try run(
            buildTimeTriple: buildTimeTriple,
            runTimeTriple: runTimeTriple,
            destination,
            configurationStore,
            destinationsDirectory,
            observabilityScope
        )
    }
}
