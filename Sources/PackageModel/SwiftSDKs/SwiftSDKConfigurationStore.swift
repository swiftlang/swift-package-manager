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
}
