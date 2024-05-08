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

import var TSCBasic.stdoutStream

struct ConfigureSwiftSDK: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "configure",
        abstract: """
        Manages configuration options for installed Swift SDKs.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Option(help: "A path to a directory containing the SDK root.")
    var sdkRootPath: String? = nil

    @Option(help: "A path to a directory containing Swift resources for dynamic linking.")
    var swiftResourcesPath: String? = nil

    @Option(help: "A path to a directory containing Swift resources for static linking.")
    var swiftStaticResourcesPath: String? = nil

    @Option(
        parsing: .singleValue,
        help: """
        A path to a directory containing headers. Multiple paths can be specified by providing this option multiple \
        times to the command.
        """
    )
    var includeSearchPath: [String] = []

    @Option(
        parsing: .singleValue,
        help: """
        "A path to a directory containing libraries. Multiple paths can be specified by providing this option multiple \
        times to the command.
        """
    )
    var librarySearchPath: [String] = []

    @Option(
        parsing: .singleValue,
        help: """
        "A path to a toolset file. Multiple paths can be specified by providing this option multiple times to the command.
        """
    )
    var toolsetPath: [String] = []

    @Flag(
        name: .customLong("reset"),
        help: """
        Resets configuration properties currently applied to a given Swift SDK and target triple. If no specific \
        property is specified, all of them are reset for the Swift SDK.
        """
    )
    var shouldReset: Bool = false

    @Flag(
        name: .customLong("show-configuration"),
        help: """
        Prints all configuration properties currently applied to a given Swift SDK and target triple.
        """
    )
    var shouldShowConfiguration: Bool = false

    @Argument(
        help: """
        An identifier of an already installed Swift SDK. Use the `list` subcommand to see all available \
        identifiers.
        """
    )
    var sdkID: String

    @Argument(help: "The target triple of the Swift SDK to configure.")
    var targetTriple: String

    /// The file system used by default by this command.
    private var fileSystem: FileSystem { localFileSystem }

    /// Parses Swift SDKs directory option if provided or uses the default path for Swift SDKs
    /// on the file system. A new directory at this path is created if one doesn't exist already.
    /// - Returns: existing or a newly created directory at the computed location.
    private func getOrCreateSwiftSDKsDirectory() throws -> AbsolutePath {
        var swiftSDKsDirectory = try fileSystem.getSharedSwiftSDKsDirectory(
            explicitDirectory: locations.swiftSDKsDirectory
        )

        if !self.fileSystem.exists(swiftSDKsDirectory) {
            swiftSDKsDirectory = try self.fileSystem.getOrCreateSwiftPMSwiftSDKsDirectory()
        }

        return swiftSDKsDirectory
    }

    func run() async throws {
        let observabilityHandler = SwiftCommandObservabilityHandler(outputStream: stdoutStream, logLevel: .info)
        let observabilitySystem = ObservabilitySystem(observabilityHandler)
        let observabilityScope = observabilitySystem.topScope
        let swiftSDKsDirectory = try self.getOrCreateSwiftSDKsDirectory()

        let hostToolchain = try UserToolchain(swiftSDK: SwiftSDK.hostSwiftSDK())
        let triple = try Triple.getHostTriple(usingSwiftCompiler: hostToolchain.swiftCompilerPath)

        var commandError: Error? = nil
        do {
            let bundleStore = SwiftSDKBundleStore(
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem: self.fileSystem,
                observabilityScope: observabilityScope,
                outputHandler: { print($0) }
            )
            let configurationStore = try SwiftSDKConfigurationStore(
                hostTimeTriple: triple,
                swiftSDKBundleStore: bundleStore
            )
            let targetTriple = try Triple(self.targetTriple)

            guard let swiftSDK = try configurationStore.readConfiguration(
                sdkID: sdkID,
                targetTriple: targetTriple
            ) else {
                throw SwiftSDKError.swiftSDKNotFound(
                    artifactID: sdkID,
                    hostTriple: triple,
                    targetTriple: targetTriple
                )
            }

            if self.shouldShowConfiguration {
                print(swiftSDK.pathsConfiguration)
                return
            }

            var configuration = swiftSDK.pathsConfiguration
            if self.shouldReset {
                if try !configurationStore.resetConfiguration(sdkID: sdkID, targetTriple: targetTriple) {
                    observabilityScope.emit(
                        warning: "No configuration for Swift SDK `\(sdkID)`"
                    )
                } else {
                    observabilityScope.emit(
                        info: """
                        All configuration properties of Swift SDK `\(sdkID)` for target triple \
                        `\(targetTriple)` were successfully reset.
                        """
                    )
                }
            } else {
                var updatedProperties = [String]()

                let currentWorkingDirectory: AbsolutePath? = fileSystem.currentWorkingDirectory

                if let sdkRootPath {
                    configuration.sdkRootPath = try AbsolutePath(validating: sdkRootPath, relativeTo: currentWorkingDirectory)
                    updatedProperties.append(CodingKeys.sdkRootPath.stringValue)
                }

                if let swiftResourcesPath {
                    configuration.swiftResourcesPath =
                        try AbsolutePath(validating: swiftResourcesPath, relativeTo: currentWorkingDirectory)
                    updatedProperties.append(CodingKeys.swiftResourcesPath.stringValue)
                }

                if let swiftStaticResourcesPath {
                    configuration.swiftResourcesPath =
                        try AbsolutePath(validating: swiftStaticResourcesPath, relativeTo: currentWorkingDirectory)
                    updatedProperties.append(CodingKeys.swiftStaticResourcesPath.stringValue)
                }

                if !includeSearchPath.isEmpty {
                    configuration.includeSearchPaths =
                        try includeSearchPath.map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) }
                    updatedProperties.append(CodingKeys.includeSearchPath.stringValue)
                }

                if !librarySearchPath.isEmpty {
                    configuration.librarySearchPaths =
                        try librarySearchPath.map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) }
                    updatedProperties.append(CodingKeys.librarySearchPath.stringValue)
                }

                if !toolsetPath.isEmpty {
                    configuration.toolsetPaths =
                        try toolsetPath.map { try AbsolutePath(validating: $0, relativeTo: currentWorkingDirectory) }
                    updatedProperties.append(CodingKeys.toolsetPath.stringValue)
                }

                guard !updatedProperties.isEmpty else {
                    observabilityScope.emit(
                        error: """
                        No properties of Swift SDK `\(sdkID)` for target triple `\(targetTriple)` were updated \
                        since none were specified. Pass `--help` flag to see the list of all available properties.
                        """
                    )
                    return
                }

                var swiftSDK = swiftSDK
                swiftSDK.pathsConfiguration = configuration
                try configurationStore.updateConfiguration(sdkID: sdkID, swiftSDK: swiftSDK)

                observabilityScope.emit(
                    info: """
                    These properties of Swift SDK `\(sdkID)` for target triple \
                    `\(targetTriple)` were successfully updated: \(updatedProperties.joined(separator: ", ")).
                    """
                )
            }            

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

extension AbsolutePath {
    fileprivate init(validating string: String, relativeTo basePath: AbsolutePath?) throws {
        if let basePath {
            try self.init(validating: string, relativeTo: basePath)
        } else {
            try self.init(validating: string)
        }
    }
}
