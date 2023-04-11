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
import Foundation
import PackageModel

import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem
import var TSCBasic.stdoutStream
import func TSCBasic.tsc_await

public struct InstallDestination: DestinationCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: """
        Installs a given destination artifact bundle to a location discoverable by SwiftPM. If the artifact bundle \
        is at a remote location, it's downloaded to local filesystem first.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(help: "A local filesystem path or a URL of an artifact bundle to install.")
    var bundlePathOrURL: String

    public init() {}

    func run(
        buildTimeTriple: Triple,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws {
        let cancellator = Cancellator(observabilityScope: observabilityScope)
        cancellator.installSignalHandlers()
        try DestinationBundle.install(
            bundlePathOrURL: bundlePathOrURL,
            destinationsDirectory: destinationsDirectory,
            self.fileSystem,
            UniversalArchiver(self.fileSystem, cancellator),
            observabilityScope
        )
    }
}
