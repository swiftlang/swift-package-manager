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

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// Storage for configuration properties of Swift SDKs.
public final class SwiftSDKConfigurationStore {
    /// Triple of the machine on which SwiftPM is running.
    private let hostTriple: Triple

    /// Path to the directory in which Swift SDKs and their configuration are stored. Usually
    /// `~/.swiftpm/swift-sdks` or a directory to which `~/.swiftpm/swift-sdks` symlinks to.
    private let swiftSDKsDirectoryPath: AbsolutePath

    /// Path to the directory in which Swift SDK configuration files are stored.
    private let configurationDirectoryPath: AbsolutePath

    /// File system that stores Swift SDK configuration and contains
    /// ``SwiftSDKConfigurationStore//configurationDirectoryPath``.
    private let fileSystem: FileSystem

    // An observability scope on which warnings can be reported if any appear.
    private let swiftSDKBundleStore: SwiftSDKBundleStore

    /// Encoder used for encoding updated configuration to be written to ``SwiftSDKConfigurationStore//fileSystem``.
    private let encoder: JSONEncoder

    /// Encoder used for reading existing configuration from  ``SwiftSDKConfigurationStore//fileSystem``.
    private let decoder: JSONDecoder

    /// Initializes a store for configuring Swift SDKs.
    /// - Parameters:
    ///   - hostTriple: Triple of the machine on which SwiftPM is running.
    ///   - swiftSDKsDirectoryPath: Path to the directory in which Swift SDKs and their configuration are
    ///   stored. Usually `~/.swiftpm/swift-sdks` or a directory to which `~/.swiftpm/swift-sdks` symlinks to.
    ///   If this directory doesn't exist, an error will be thrown.
    ///   - fileSystem: file system on which `swiftSDKsDirectoryPath` exists.
    ///   - observabilityScope: an observability scope on which warnings can be reported if any appear.
    public init(
        hostTimeTriple: Triple,
        swiftSDKBundleStore: SwiftSDKBundleStore
    ) throws {
        let configurationDirectoryPath = swiftSDKBundleStore.swiftSDKsDirectory.appending(component: "configuration")

        let fileSystem = swiftSDKBundleStore.fileSystem
        if fileSystem.exists(configurationDirectoryPath) {
            guard fileSystem.isDirectory(configurationDirectoryPath) else {
                throw SwiftSDKError.pathIsNotDirectory(configurationDirectoryPath)
            }
        } else {
            try fileSystem.createDirectory(configurationDirectoryPath)
        }

        self.hostTriple = hostTimeTriple
        self.swiftSDKsDirectoryPath = swiftSDKBundleStore.swiftSDKsDirectory
        self.configurationDirectoryPath = configurationDirectoryPath
        self.fileSystem = fileSystem
        self.swiftSDKBundleStore = swiftSDKBundleStore
        self.encoder = JSONEncoder.makeWithDefaults(prettified: true)
        self.decoder = JSONDecoder.makeWithDefaults()
    }

    public func updateConfiguration(
        sdkID: String,
        swiftSDK: SwiftSDK
    ) throws {
        let (targetTriple, properties) = try swiftSDK.serialized

        let configurationPath = configurationDirectoryPath.appending(
            component: "\(sdkID)_\(targetTriple).json"
        )

        try encoder.encode(path: configurationPath, fileSystem: fileSystem, properties)
    }

    private func swiftSDKs(for id: String) throws -> [SwiftSDK] {
        for bundle in try self.swiftSDKBundleStore.allValidBundles {
            for (artifactID, variants) in bundle.artifacts {
                guard artifactID == id else {
                    continue
                }

                for variant in variants {
                    return variant.swiftSDKs
                }
            }
        }

        return []
    }

    public func readConfiguration(
        sdkID: String,
        targetTriple: Triple
    ) throws -> SwiftSDK? {
        let configurationPath = configurationDirectoryPath.appending(
            component: "\(sdkID)_\(targetTriple.tripleString).json"
        )

        let swiftSDKs = try self.swiftSDKBundleStore.allValidBundles

        guard var swiftSDK = swiftSDKs.selectSwiftSDK(
            id: sdkID,
            hostTriple: nil,
            targetTriple: targetTriple
        ) else {
            return nil
        }

        if fileSystem.isFile(configurationPath) {
            let properties = try decoder.decode(
                path: configurationPath,
                fileSystem: fileSystem,
                as: SwiftSDKMetadataV4.TripleProperties.self
            )

            swiftSDK.pathsConfiguration.merge(
                with: try SwiftSDK(
                    targetTriple: targetTriple,
                    properties: properties
                ).pathsConfiguration
            )
        }

        return swiftSDK
    }

    /// Resets configuration for identified target triple.
    /// - Parameters:
    ///   - sdkID: ID of the Swift SDK to operate on.
    ///   - tripleString: run-time triple for which the properties should be reset.
    /// - Returns: `true` if custom configuration was successfully removed, `false` if no custom configuration existed.
    public func resetConfiguration(
        sdkID: String,
        targetTriple triple: Triple
    ) throws -> Bool {
        let configurationPath = configurationDirectoryPath.appending(
            component: "\(sdkID)_\(triple.tripleString).json"
        )

        guard fileSystem.isFile(configurationPath) else {
            return false
        }

        try fileSystem.removeFileTree(configurationPath)
        return true
    }

    /// Configures the specified Swift SDK and identified target triple with the configuration parameter.
    /// - Parameters:
    ///   - sdkID: ID of the Swift SDK to operate on.
    ///   - tripleString: run-time triple for which the properties should be configured, or nil to configure all triples for the Swift SDK
    ///   - showConfiguration: if true, simply print the current configuration for the target triple(s)
    ///   - resetConfiguration: if true, reset the configuration for the target triple(s)
    ///   - config: the configuration parameters to set for for the target triple(s)
    /// - Returns: `true` if custom configuration was successful, `false` if no configuration was performed.
    package func configure(
        sdkID: String,
        targetTriple: String?,
        showConfiguration: Bool,
        resetConfiguration: Bool,
        config: SwiftSDK.PathsConfiguration<String>
    ) throws -> Bool {
        let targetTriples: [Triple]
        if let targetTriple = targetTriple {
            targetTriples = try [Triple(targetTriple)]
        } else {
            // when `targetTriple` is unspecified, configure every triple for the SDK
            let validBundles = try self.swiftSDKs(for: sdkID)
            targetTriples = validBundles.compactMap(\.targetTriple)
            if targetTriples.isEmpty {
                throw SwiftSDKError.swiftSDKNotFound(
                    artifactID: sdkID,
                    hostTriple: hostTriple,
                    targetTriple: nil
                )
            }
        }

        for targetTriple in targetTriples {
            guard let swiftSDK = try self.readConfiguration(
                sdkID: sdkID,
                targetTriple: targetTriple
            ) else {
                throw SwiftSDKError.swiftSDKNotFound(
                    artifactID: sdkID,
                    hostTriple: hostTriple,
                    targetTriple: targetTriple
                )
            }

            if showConfiguration {
                print(swiftSDK.pathsConfiguration)
                continue
            }

            if resetConfiguration {
                if try !self.resetConfiguration(sdkID: sdkID, targetTriple: targetTriple) {
                    swiftSDKBundleStore.observabilityScope.emit(
                        warning: "No configuration for Swift SDK `\(sdkID)`"
                    )
                } else {
                    swiftSDKBundleStore.observabilityScope.emit(
                        info: """
                        All configuration properties of Swift SDK `\(sdkID)` for target triple \
                        `\(targetTriple)` were successfully reset.
                        """
                    )
                }
            } else {
                var configuration = swiftSDK.pathsConfiguration
                let updatedProperties = try configuration.merge(with: config, relativeTo: fileSystem.currentWorkingDirectory)

                guard !updatedProperties.isEmpty else {
                    swiftSDKBundleStore.observabilityScope.emit(
                        error: """
                        No properties of Swift SDK `\(sdkID)` for target triple `\(targetTriple)` were updated \
                        since none were specified. Pass `--help` flag to see the list of all available properties.
                        """
                    )
                    return false
                }

                var swiftSDK = swiftSDK
                swiftSDK.pathsConfiguration = configuration
                swiftSDK.targetTriple = targetTriple
                try self.updateConfiguration(sdkID: sdkID, swiftSDK: swiftSDK)

                swiftSDKBundleStore.observabilityScope.emit(
                    info: """
                    These properties of Swift SDK `\(sdkID)` for target triple \
                    `\(targetTriple)` were successfully updated: \(updatedProperties.joined(separator: ", ")).
                    """
                )
            }

            if swiftSDKBundleStore.observabilityScope.errorsReported {
                return false
            }
        }

        return true
    }
}
