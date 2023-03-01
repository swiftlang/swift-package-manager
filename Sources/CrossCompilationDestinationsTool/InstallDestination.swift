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

import func TSCBasic.tsc_await
import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem
import var TSCBasic.stdoutStream

public struct InstallDestination: ParsableCommand {
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

    public func run() throws {
        let fileSystem = localFileSystem

        guard var destinationsDirectory = try fileSystem.getSharedCrossCompilationDestinationsDirectory(
            explicitDirectory: locations.crossCompilationDestinationsDirectory
        ) else {
            let expectedPath = try fileSystem.swiftPMCrossCompilationDestinationsDirectory
            throw StringError(
                "Couldn't find or create a directory where cross-compilation destinations are stored: `\(expectedPath)`"
            )
        }

        // FIXME: generalize path calculation and creation with `ListDestinations` subcommand
        if !fileSystem.exists(destinationsDirectory) {
            destinationsDirectory = try fileSystem.getOrCreateSwiftPMCrossCompilationDestinationsDirectory()
        }

        let observabilitySystem = ObservabilitySystem.swiftTool(logLevel: .info)
        let observabilityScope = observabilitySystem.topScope

        if
            let bundleURL = URL(string: bundlePathOrURL),
            let scheme = bundleURL.scheme,
                scheme == "http" || scheme == "https"
        {
            let response = try tsc_await { (completion: @escaping (Result<HTTPClientResponse, Error>) -> Void) in
                let client = LegacyHTTPClient()
                client.execute(.init(method: .get, url: bundleURL), progress: nil, completion: completion)
            }

            guard let body = response.body else {
                throw StringError("No downloadable data available at URL `\(bundleURL)`.")
            }

            let fileName = bundleURL.lastPathComponent

            try fileSystem.writeFileContents(destinationsDirectory.appending(component: fileName), data: body)
        } else if
            let cwd = fileSystem.currentWorkingDirectory,
            let bundlePath = try? AbsolutePath(validating: bundlePathOrURL, relativeTo: cwd),
            let bundleName = bundlePath.components.last,
            fileSystem.exists(bundlePath)
        {
            let destinationPath = destinationsDirectory.appending(component: bundleName)
            if fileSystem.exists(destinationPath) {
                throw StringError("Destination artifact bundle with name `\(bundleName)` is already installed.")
            } else {
                try fileSystem.copy(from: bundlePath, to: destinationPath)
            }
        } else {
            throw StringError("Argument `\(bundlePathOrURL)` is neither a valid filesystem path nor a URL.")
        }

        observabilityScope.emit(info: "Destination artifact bundle at `\(bundlePathOrURL)` successfully installed.")
    }
}
