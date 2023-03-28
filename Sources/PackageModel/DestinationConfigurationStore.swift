//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import TSCBasic

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// Storage for configuration properties of cross-compilation destinations.
public final class DestinationConfigurationStore {
    /// Triple of the machine on which SwiftPM is running.
    private let buildTimeTriple: Triple

    /// Path to the directory in which destinations and their configuration are stored. Usually
    /// `~/.swiftpm/destinations` or a directory to which `~/.swiftpm/destinations` symlinks to.
    private let destinationsDirectoryPath: AbsolutePath

    /// Path to the directory in which destination configuration files are stored.
    private let configurationDirectoryPath: AbsolutePath

    /// File system that stores destination configuration and contains
    /// ``DestinationConfigurationStore//configurationDirectoryPath``.
    private let fileSystem: FileSystem

    // An observability scope on which warnings can be reported if any appear.
    private let observabilityScope: ObservabilityScope

    /// Encoder used for encoding updated configuration to be written to ``DestinationConfigurationStore//fileSystem``.
    private let encoder: JSONEncoder

    /// Encoder used for reading existing configuration from  ``DestinationConfigurationStore//fileSystem``.
    private let decoder: JSONDecoder

    /// Initializes a store for configuring destinations.
    /// - Parameters:
    ///   - buildTimeTriple: Triple of the machine on which SwiftPM is running.
    ///   - destinationsDirectoryPath: Path to the directory in which destinations and their configuration are
    ///   stored. Usually `~/.swiftpm/destinations` or a directory to which `~/.swiftpm/destinations` symlinks to.
    ///   If this directory doesn't exist, an error will be thrown.
    ///   - fileSystem: file system on which `destinationsDirectoryPath` exists.
    ///   - observabilityScope: an observability scope on which warnings can be reported if any appear.
    public init(
        buildTimeTriple: Triple,
        destinationsDirectoryPath: AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        let configurationDirectoryPath = destinationsDirectoryPath.appending(component: "configuration")

        if fileSystem.exists(configurationDirectoryPath) {
            guard fileSystem.isDirectory(configurationDirectoryPath) else {
                throw DestinationError.pathIsNotDirectory(configurationDirectoryPath)
            }
        } else {
            try fileSystem.createDirectory(configurationDirectoryPath)
        }

        self.buildTimeTriple = buildTimeTriple
        self.destinationsDirectoryPath = destinationsDirectoryPath
        self.configurationDirectoryPath = configurationDirectoryPath
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
        self.encoder = JSONEncoder.makeWithDefaults(prettified: true)
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    public func updateConfiguration(
        destinationID: String,
        destination: Destination
    ) throws {
        let (runTimeTriple, properties) = try destination.serialized

        let configurationPath = configurationDirectoryPath.appending(
            component: "\(destinationID)_\(runTimeTriple).json"
        )

        try encoder.encode(path: configurationPath, fileSystem: fileSystem, properties)
    }

    public func readConfiguration(
        destinationID: String,
        runTimeTriple triple: Triple
    ) throws -> Destination? {
        let configurationPath = configurationDirectoryPath.appending(
            component: "\(destinationID)_\(triple.tripleString).json"
        )

        let destinationBundles = try DestinationBundle.getAllValidBundles(
            destinationsDirectory: destinationsDirectoryPath,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        guard var destination = destinationBundles.selectDestination(
            id: destinationID,
            hostTriple: buildTimeTriple,
            targetTriple: triple
        ) else {
            return nil
        }

        if fileSystem.isFile(configurationPath) {
            let properties = try decoder.decode(
                path: configurationPath,
                fileSystem: fileSystem,
                as: SerializedDestinationV3.TripleProperties.self
            )

            destination.pathsConfiguration.merge(
                with: try Destination(
                    runTimeTriple: triple,
                    properties: properties
                ).pathsConfiguration
            )
        }

        return destination
    }

    /// Resets configuration for identified destination triple.
    /// - Parameters:
    ///   - destinationID: ID of the destination to operate on.
    ///   - tripleString: run-time triple for which the properties should be reset.
    /// - Returns: `true` if custom configuration was successfully removed, `false` if no custom configuration existed.
    public func resetConfiguration(
        destinationID: String,
        runTimeTriple triple: Triple
    ) throws -> Bool {
        let configurationPath = configurationDirectoryPath.appending(
            component: "\(destinationID)_\(triple.tripleString).json"
        )

        guard fileSystem.isFile(configurationPath) else {
            return false
        }

        try fileSystem.removeFileTree(configurationPath)
        return true
    }
}
