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

struct ListAliases: SwiftSDKSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available Swift SDK aliases from the remote index."
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

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

        let aliases = try await aliasStore.listAliases(httpClient: HTTPClient())

        if aliases.isEmpty {
            print("No Swift SDK aliases available.")
        } else {
            for alias in aliases {
                print(alias)
            }
        }
    }
}
