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
import Dispatch
import PackageModel

import struct TSCBasic.AbsolutePath
import protocol TSCBasic.FileSystem
import var TSCBasic.localFileSystem
import var TSCBasic.stdoutStream

/// A protocol for functions and properties common to all destination subcommands.
protocol DestinationCommand: ParsableCommand {
    /// Common locations options provided by ArgumentParser.
    var locations: LocationOptions { get }

    /// Run a command operating on cross-compilation destinations, passing it required configuration values.
    /// - Parameters:
    ///   - buildTimeTriple: triple of the machine this command is running on.
    ///   - destinationsDirectory: directory containing destination artifact bundles and their configuration.
    ///   - observabilityScope: observability scope used for logging.
    func run(
        buildTimeTriple: Triple,
        _ destinationsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) throws
}

extension DestinationCommand {
    /// The file system used by default by this command.
    var fileSystem: FileSystem { localFileSystem }

    /// Parses destinations directory option if provided or uses the default path for cross-compilation destinations
    /// on the file system. A new directory at this path is created if one doesn't exist already.
    /// - Returns: existing or a newly created directory at the computed location.
    func getOrCreateDestinationsDirectory() throws -> AbsolutePath {
        guard var destinationsDirectory = try fileSystem.getSharedCrossCompilationDestinationsDirectory(
            explicitDirectory: locations.crossCompilationDestinationsDirectory
        ) else {
            let expectedPath = try fileSystem.swiftPMCrossCompilationDestinationsDirectory
            throw StringError(
                "Couldn't find or create a directory where cross-compilation destinations are stored: `\(expectedPath)`"
            )
        }

        if !self.fileSystem.exists(destinationsDirectory) {
            destinationsDirectory = try self.fileSystem.getOrCreateSwiftPMCrossCompilationDestinationsDirectory()
        }

        return destinationsDirectory
    }

    public func run() throws {
        let observabilityHandler = SwiftToolObservabilityHandler(outputStream: stdoutStream, logLevel: .info)
        let observabilitySystem = ObservabilitySystem(observabilityHandler)
        let observabilityScope = observabilitySystem.topScope
        let destinationsDirectory = try self.getOrCreateDestinationsDirectory()

        let hostToolchain = try UserToolchain(destination: Destination.hostDestination())
        let triple = try Triple.getHostTriple(usingSwiftCompiler: hostToolchain.swiftCompilerPath)

        var commandError: Error? = nil
        do {
            try self.run(buildTimeTriple: triple, destinationsDirectory, observabilityScope)
            if observabilityScope.errorsReported {
                throw ExitCode.failure
            }
        } catch {
            commandError = error
        }

        // wait for all observability items to process
        observabilityHandler.wait(timeout: .now() + 5)

        if let commandError {
            throw commandError
        }
    }
}
