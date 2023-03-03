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
import TSCBasic

public struct ListDestinations: DestinationCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract:
        """
        Print a list of IDs of available cross-compilation destinations available on the filesystem.
        """
    )

    @OptionGroup()
    var locations: LocationOptions

    public init() {}

    public func run() throws {
        let observabilitySystem = ObservabilitySystem.swiftTool()
        let observabilityScope = observabilitySystem.topScope
        let destinationsDirectory = try self.getOrCreateDestinationsDirectory()

        let validBundles = try DestinationBundle.getAllValidBundles(
            destinationsDirectory: destinationsDirectory,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        for bundle in validBundles {
            bundle.artifacts.keys.forEach { print($0) }
        }
    }
}
