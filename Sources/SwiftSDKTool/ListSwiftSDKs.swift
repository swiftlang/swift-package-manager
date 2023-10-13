//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
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
import SPMBuildCore

public struct ListSwiftSDKs: SwiftSDKSubcommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract:
        """
        Print a list of IDs of available Swift SDKs available on the filesystem.
        """
    )

    @OptionGroup()
    var locations: LocationOptions

    public init() {}

    func run(
        hostTriple: Triple,
        _ swiftSDKsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        let store = SwiftSDKBundleStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            outputHandler: { print($0.description) }
        )
        let validBundles = try store.allValidBundles

        guard !validBundles.isEmpty else {
            print("No Swift SDKs are currently installed.")
            return
        }

        for artifactID in validBundles.sortedArtifactIDs {
            print(artifactID)
        }
    }
}
