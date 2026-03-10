//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2026 Apple Inc. and the Swift project authors
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
import Foundation
import PackageModel

import var TSCBasic.stdoutStream
import class Workspace.Workspace

struct InstallSwiftSDK: SwiftSDKSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: """
        Installs a given Swift SDK bundle to a location discoverable by SwiftPM. If the artifact bundle \
        is at a remote location, it's downloaded to local filesystem first. An alias name (e.g. "wasi") \
        can be used instead of a URL to automatically resolve the correct SDK for the current toolchain.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(help: "A local filesystem path, a URL of a Swift SDK bundle, or an alias name to install.")
    var bundlePathOrURL: String

    @Option(help: "The checksum of the bundle generated with `swift package compute-checksum`.")
    var checksum: String? = nil

    @Flag(
        name: .customLong("color-diagnostics"),
        inversion: .prefixedNo,
        help: """
            Enables or disables color diagnostics when printing to a TTY.
            By default, color diagnostics are enabled when connected to a TTY and disabled otherwise.
            """
    )
    public var colorDiagnostics: Bool = ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    func run(
        hostTriple: Triple,
        hostToolchain: UserToolchain,
        _ swiftSDKsDirectory: AbsolutePath,
        _ observabilityScope: ObservabilityScope
    ) async throws {
        let cancellator = Cancellator(observabilityScope: observabilityScope)
        cancellator.installSignalHandlers()

        let httpClient = HTTPClient()
        var resolvedBundlePathOrURL = bundlePathOrURL
        var resolvedChecksum = self.checksum

        // Detect if the argument is an alias (not a URL and not an existing filesystem path)
        if !self.looksLikeURLOrPath(bundlePathOrURL) {
            let aliasStore = SwiftSDKAliasStore(
                swiftSDKsDirectory: swiftSDKsDirectory,
                fileSystem: self.fileSystem,
                observabilityScope: observabilityScope
            )

            guard let compilerTag = hostToolchain.swiftCompilerVersion else {
                throw SwiftSDKAliasError.unknownCompilerVersion
            }

            if self.checksum != nil {
                observabilityScope.emit(
                    warning: "The --checksum option is ignored when installing via an alias. " +
                    "The checksum is provided by the alias index."
                )
            }

            let resolved = try await aliasStore.resolve(
                alias: bundlePathOrURL,
                swiftCompilerTag: compilerTag,
                httpClient: httpClient
            )

            resolvedBundlePathOrURL = resolved.url
            resolvedChecksum = resolved.checksum
            print("Resolved alias '\(bundlePathOrURL)' to Swift SDK '\(resolved.id)'.")
        }

        let store = SwiftSDKBundleStore(
            swiftSDKsDirectory: swiftSDKsDirectory,
            hostToolchainBinDir: hostToolchain.swiftCompilerPath.parentDirectory,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope,
            outputHandler: { print($0.description) },
            downloadProgressAnimation: ProgressAnimation
                .percent(
                    stream: stdoutStream,
                    verbose: false,
                    header: "Downloading",
                    isColorized: self.colorDiagnostics
                )
                .throttled(interval: .milliseconds(300))
        )

        try await store.install(
            bundlePathOrURL: resolvedBundlePathOrURL,
            checksum: resolvedChecksum,
            UniversalArchiver(self.fileSystem, cancellator),
            httpClient,
            hasher: {
                try Workspace.BinaryArtifactsManager.checksum(
                    forBinaryArtifactAt: $0,
                    fileSystem: self.fileSystem
                )
            }
        )
    }

    /// Returns `true` if the argument looks like a URL or an existing filesystem path,
    /// `false` if it should be treated as an alias.
    private func looksLikeURLOrPath(_ argument: String) -> Bool {
        // Check for URL schemes
        if argument.hasPrefix("http://") || argument.hasPrefix("https://") || argument.hasPrefix("file://") {
            return true
        }

        // Check for absolute filesystem paths
        if argument.hasPrefix("/") || argument.hasPrefix("~") {
            return true
        }

        // Check for Windows-style absolute paths
        if argument.count >= 2, argument[argument.index(after: argument.startIndex)] == ":" {
            return true
        }

        // Check for relative paths with path separators
        if argument.contains("/") || argument.contains("\\") {
            return true
        }

        // Check if it exists as a local file
        if let path = try? AbsolutePath(validating: argument, relativeTo: fileSystem.currentWorkingDirectory ?? .root),
           fileSystem.exists(path) {
            return true
        }

        return false
    }
}
