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
import SPMBuildCore
import PackageModel
import TSCBasic

public struct ListDestinations: ParsableCommand {
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
        let fileSystem = localFileSystem
        let observabilitySystem = ObservabilitySystem.swiftTool()
        let observabilityScope = observabilitySystem.topScope

        guard var destinationsDirectory = try fileSystem.getSharedCrossCompilationDestinationsDirectory(
            explicitDirectory: locations.crossCompilationDestinationsDirectory
        ) else {
            let expectedPath = try fileSystem.swiftPMCrossCompilationDestinationsDirectory
            throw StringError(
                "Couldn't find or create a directory where cross-compilation destinations are stored: \(expectedPath)"
            )
        }

        if !fileSystem.exists(destinationsDirectory) {
            destinationsDirectory = try fileSystem.getOrCreateSwiftPMCrossCompilationDestinationsDirectory()
        }

        let validBundles = try DestinationsBundle.getAllValidBundles(
            destinationsDirectory: destinationsDirectory,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )

        for bundle in validBundles {
            bundle.artifacts.keys.forEach { print($0) }
        }
    }
}
