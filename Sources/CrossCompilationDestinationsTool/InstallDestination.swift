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

import struct TSCBasic.AbsolutePath
import var TSCBasic.localFileSystem
import var TSCBasic.stdoutStream

@available(macOS 12, *)
struct InstallDestination: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: """
        Installs a given destination artifact bundle to a location discoverable for SwiftPM. If the artifact bundle
        is at a remote location, it's downloaded to local filesystem first.
        """
    )

    @OptionGroup()
    var locations: LocationOptions

    @Argument(help: "URL or a local filesystem path of an artifact bundle to install.")
    var bundlePathOrURL: String

    func run() async throws {
        let fileSystem = localFileSystem

        guard var destinationsDirectory = try fileSystem.getSharedCrossCompilationDestinationsDirectory(
            explicitDirectory: locations.crossCompilationDestinationsDirectory
        ) else {
            let expectedPath = try fileSystem.swiftPMCrossCompilationDestinationsDirectory
            throw StringError(
                "Couldn't find or create a directory where cross-compilation destinations are stored: \(expectedPath)"
            )
        }

        // FIXME: generalize path calculation and creation with `ListDestinations` subcommand
        if !fileSystem.exists(destinationsDirectory) {
            destinationsDirectory = try fileSystem.getOrCreateSwiftPMCrossCompilationDestinationsDirectory()
        }

        let observabilitySystem = ObservabilitySystem(
            SwiftToolObservabilityHandler(outputStream: stdoutStream, logLevel: .warning)
        )
        let observabilityScope = observabilitySystem.topScope

        if let bundleURL = URL(string: bundlePathOrURL) {
            let client = URLSessionHTTPClient()
            let response = try await client.execute(.init(method: .get, url: bundleURL), progress: nil)

            guard let body = response.body else {
                observabilityScope.emit(error: "No downloadable data available at URL \(bundleURL).")
                return
            }

            let fileName = bundleURL.lastPathComponent

            try fileSystem.writeFileContents(destinationsDirectory.appending(component: fileName), data: body)
        } else if
            let cwd = fileSystem.currentWorkingDirectory,
            let bundlePath = try? AbsolutePath(validating: bundlePathOrURL, relativeTo: cwd)
        {
            try fileSystem.move(from: bundlePath, to: destinationsDirectory)
        } else {
            observabilityScope.emit(error: "Argument \(bundlePathOrURL) is neither a valid filesystem path nor a URL.")
        }
    }
}
