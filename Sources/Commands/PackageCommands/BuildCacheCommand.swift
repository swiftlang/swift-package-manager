//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
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
import Workspace

extension SwiftPackageCommand {
    struct BuildCache: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build-cache",
            abstract: "Configure the build cache.",
            subcommands: [Configure.self, Reset.self, GetConfiguration.self, Clear.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )
    }
}

extension SwiftPackageCommand.BuildCache {
    /// Whether to read/write the local (per-package) or shared (global) configuration.
    fileprivate struct ScopeOptions: ParsableArguments {
        @Flag(
            name: .customLong("global"),
            help: "Apply to the shared global configuration instead of the local package configuration."
        )
        var global: Bool = false
    }

    /// Apply a mutation to the local or shared configuration, depending on `scope`.
    fileprivate static func update(
        _ config: Workspace.Configuration.BuildCache,
        scope: ScopeOptions,
        handler: (inout BuildCacheConfiguration) throws -> Void
    ) throws {
        if scope.global {
            try config.updateShared(handler: handler)
        } else {
            try config.updateLocal(handler: handler)
        }
    }

    struct Configure: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "configure",
            abstract: "Configure build cache options."
        )

        /// Whether to enable or disable build caching in the configuration.
        fileprivate enum Enablement: EnumerableFlag {
            case enable
            case disable
        }

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Enable or disable build caching.")
        fileprivate var enablement: Enablement?

        @Option(help: "The on-disk location of the build cache.", completion: .directory)
        var path: AbsolutePath?

        @Option(help: "Limit the cache size, either as an absolute size (e.g. '10G') or as a percentage of available disk space (e.g. '50%').")
        var sizeLimit: String?

        @Flag(
            name: .customLong("diagnostic-remarks"),
            inversion: .prefixedNo,
            help: "Emit diagnostic remarks about build cache hits and misses."
        )
        var diagnosticRemarks: Bool?

        @Option(help: "The path to a remote build cache service.", completion: .directory)
        var remoteServicePath: AbsolutePath?

        @Option(help: "The path to an LLVM-compatible build cache plugin.", completion: .directory)
        var pluginPath: AbsolutePath?

        @Flag(
            name: .customLong("prefix-mapping"),
            inversion: .prefixedNo,
            help: "Enable or disable prefix mapping for build caching."
        )
        var prefixMapping: Bool?

        @OptionGroup
        fileprivate var scope: ScopeOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            if self.enablement == nil, self.path == nil, self.sizeLimit == nil, self.diagnosticRemarks == nil,
               self.remoteServicePath == nil, self.pluginPath == nil, self.prefixMapping == nil {
                swiftCommandState.observabilityScope.emit(.error("no configuration options were provided"))
                throw ExitCode.failure
            }

            let sizeLimit = try self.sizeLimit.map(BuildCacheConfiguration.SizeLimit.parse)

            let config = try getBuildCacheConfig(swiftCommandState)
            try update(config, scope: self.scope) { configuration in
                if let enablement = self.enablement {
                    configuration.enabled = enablement == .enable
                }
                if let path = self.path {
                    configuration.casPath = path
                }
                if let sizeLimit {
                    configuration.sizeLimit = sizeLimit
                }
                if let diagnosticRemarks = self.diagnosticRemarks {
                    configuration.enableDiagnosticRemarks = diagnosticRemarks
                }
                if let remoteServicePath = self.remoteServicePath {
                    configuration.remoteServicePath = remoteServicePath
                }
                if let pluginPath = self.pluginPath {
                    configuration.pluginPath = pluginPath
                }
                if let prefixMapping = self.prefixMapping {
                    configuration.enablePrefixMapping = prefixMapping
                }
            }
        }
    }

    struct Reset: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "reset",
            abstract: "Remove all build cache configuration options."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup
        fileprivate var scope: ScopeOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getBuildCacheConfig(swiftCommandState)
            try update(config, scope: self.scope) { configuration in
                configuration = .none
            }
        }
    }

    struct GetConfiguration: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-configuration",
            abstract: "Print the effective build cache configuration."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let configuration = try getBuildCacheConfig(swiftCommandState).configuration

            let enabled = configuration.enabled.map { $0 ? "enabled" : "disabled" } ?? "unset (build system default)"
            print("build cache: \(enabled)")

            print("path: \(configuration.casPath?.pathString ?? "unset (build system default)")")

            switch configuration.sizeLimit {
            case .size(let value):
                print("size limit: \(value)")
            case .percent(let value):
                print("size limit: \(value)% of available disk space")
            case .none:
                print("size limit: unset (build system default)")
            }

            let remarks = configuration.enableDiagnosticRemarks
                .map { $0 ? "enabled" : "disabled" } ?? "unset (build system default)"
            print("diagnostic remarks: \(remarks)")

            print("remote service path: \(configuration.remoteServicePath?.pathString ?? "unset (build system default)")")

            print("plugin path: \(configuration.pluginPath?.pathString ?? "unset (build system default)")")

            let prefixMapping = configuration.enablePrefixMapping
                .map { $0 ? "enabled" : "disabled" } ?? "unset (build system default)"
            print("prefix mapping: \(prefixMapping)")
        }
    }

    struct Clear: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Delete the on-disk build cache."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let configuration = try swiftCommandState.resolveBuildCacheConfiguration()
            // Use the configured cache path if any, otherwise the shared default
            // location that would be used when caching is enabled.
            let cachePath = configuration.casPath ?? swiftCommandState.defaultBuildCacheDirectory

            let fileSystem = swiftCommandState.fileSystem
            guard fileSystem.exists(cachePath) else {
                print("No build cache found at \(cachePath.pathString)")
                return
            }
            try fileSystem.removeFileTree(cachePath)
            print("Cleared build cache at \(cachePath.pathString)")
        }
    }

    static func getBuildCacheConfig(
        _ swiftCommandState: SwiftCommandState
    ) throws -> Workspace.Configuration.BuildCache {
        let workspace = try swiftCommandState.getActiveWorkspace()
        return try .init(
            fileSystem: swiftCommandState.fileSystem,
            localBuildCacheFile: workspace.location.localBuildCacheConfigurationFile,
            sharedBuildCacheFile: workspace.location.sharedBuildCacheConfigurationFile
        )
    }
}
