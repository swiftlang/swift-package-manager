//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
@_spi(SwiftPMInternal)
import Basics
import CoreCommands
import PackageModel

struct SetAliasRemote: SwiftSDKSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "set-remote",
        abstract: "Set the remote URL for the Swift SDK alias index."
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(help: "The HTTPS URL of the alias index remote.")
    var url: String

    func run(
        hostTriple: Triple,
        hostToolchain: UserToolchain,
        _ swiftSDKsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) async throws {
        let aliasStore = SwiftSDKAliasStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope
        )

        try aliasStore.setRemote(url)
        print("Swift SDK alias remote set to '\(url)'.")
    }
}
