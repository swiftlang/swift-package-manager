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

struct ShowConfiguration: ConfigurationSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: """
        Prints all configuration properties currently applied to a given Swift SDK and target triple.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(
        help: """
        An identifier of an already installed Swift SDK. Use the `list` subcommand to see all available \
        identifiers.
        """
    )
    var sdkID: String

    @Argument(help: "The target triple of the Swift SDK to configure.")
    var targetTriple: String

    func run(
        hostTriple: Triple,
        targetTriple: Triple,
        _ swiftSDK: SwiftSDK,
        _ configurationStore: SwiftSDKConfigurationStore,
        _ swiftSDKsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        print(swiftSDK.pathsConfiguration)
    }
}
