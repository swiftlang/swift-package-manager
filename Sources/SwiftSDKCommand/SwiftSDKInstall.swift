//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2025 Apple Inc. and the Swift project authors
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

struct SwiftSDKInstall: SwiftSDKSubcommand {
    enum Error: Swift.Error, CustomStringConvertible {
        case swiftSDKNotSpecified

        var description: String {
            switch self {
            case .swiftSDKNotSpecified:
                "Specify either a URL or a local path to a Swift SDK bundle as a positional argument."
            }
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: """
        Installs a given Swift SDK bundle to a location discoverable by SwiftPM. If the artifact bundle \
        is at a remote location, it's downloaded to local filesystem first.
        """
    )

    @OptionGroup(visibility: .hidden)
    var locations: LocationOptions

    @Argument(help: "A local filesystem path or a URL of a Swift SDK bundle to install.")
    var bundlePathOrURL: String?

    @Option(help: "The checksum of the bundle generated with `swift package compute-checksum`.")
    var checksum: String? = nil

    /// Alias of a Swift SDK to install, which automatically resolves installation URL based on host toolchain version.
    @Option(help: .hidden)
    var experimentalAlias: String? = nil

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

        let bundlePathOrURL = if let experimentalAlias {
            try SwiftToolchainVersion(
                toolchain: hostToolchain,
                fileSystem: self.fileSystem
            ).urlForSwiftSDK(aliasString: experimentalAlias)
        } else if let bundlePathOrURL {
            bundlePathOrURL
        } else {
            throw Error.swiftSDKNotSpecified
        }

        try await store.install(
            bundlePathOrURL: bundlePathOrURL,
            checksum: self.checksum,
            UniversalArchiver(self.fileSystem, cancellator),
            HTTPClient(),
            hasher: {
                try Workspace.BinaryArtifactsManager.checksum(
                    forBinaryArtifactAt: $0,
                    fileSystem: self.fileSystem
                )
            }
        )
    }
}
