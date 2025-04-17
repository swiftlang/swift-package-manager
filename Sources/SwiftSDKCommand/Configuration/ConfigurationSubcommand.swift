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
import Foundation
import PackageModel

protocol ConfigurationSubcommand: SwiftSDKSubcommand {
    /// An identifier of an already installed Swift SDK.
    var sdkID: String { get }

    /// A target triple of the Swift SDK.
    var targetTriple: String { get }

    /// Run a command related to configuration of Swift SDKs, passing it required configuration
    /// values.
    /// - Parameters:
    ///   - hostTriple: triple of the machine this command is running on.
    ///   - targetTriple: triple of the machine on which cross-compiled code will run on.
    ///   - swiftSDK: Swift SDK configuration fetched that matches currently set `sdkID` and
    ///   `targetTriple`.
    ///   - configurationStore: storage for configuration properties that this command operates on.
    ///   - swiftSDKsDirectory: directory containing Swift SDK artifact bundles and their configuration.
    ///   - observabilityScope: observability scope used for logging.
    func run(
        hostTriple: Triple,
        targetTriple: Triple,
        _ swiftSDK: SwiftSDK,
        _ configurationStore: SwiftSDKConfigurationStore,
        _ swiftSDKsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws
}

extension ConfigurationSubcommand {
    func run(
        hostTriple: Triple,
        _ swiftSDKsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        fputs("warning: `swift sdk configuration` command is deprecated and will be removed in a future version of SwiftPM. Use `swift sdk configure` instead.\n", stderr)

        let bundleStore = SwiftSDKBundleStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope,
            outputHandler: { print($0) }
        )
        let configurationStore = try SwiftSDKConfigurationStore(
            hostTimeTriple: hostTriple,
            swiftSDKBundleStore: bundleStore
        )
        let targetTriple = try Triple(self.targetTriple)

        guard let swiftSDK = try configurationStore.readConfiguration(
            sdkID: sdkID,
            targetTriple: targetTriple
        ) else {
            throw SwiftSDKError.swiftSDKNotFound(
                artifactID: sdkID,
                hostTriple: hostTriple,
                targetTriple: targetTriple
            )
        }

        try run(
            hostTriple: hostTriple,
            targetTriple: targetTriple,
            swiftSDK,
            configurationStore,
            swiftSDKsDirectory,
            observabilityScope
        )
    }
}
