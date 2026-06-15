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
import class Foundation.ByteCountFormatter
import PackageModel
import SPMBuildCore
import SwiftBuildSupport
import struct SwiftBuild.SWBBuildCacheInfo
import Workspace

extension SwiftPackageCommand {
    struct BuildCache: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "build-cache",
            abstract: "Configure the build cache.",
            subcommands: [Configure.self, ResetConfiguration.self, GetConfiguration.self, Info.self, Clean.self],
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

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(
            name: .customLong("caching"),
            inversion: .prefixedEnableDisable,
            help: "Enable or disable the build cache."
        )
        var enabled: Bool?

        @Option(help: "The path to the build cache.", completion: .directory)
        var path: AbsolutePath?

        @Option(help: "Limit the build cache size, either as an absolute size (e.g. '10G') or as a percentage of available disk space (e.g. '50%').")
        var sizeLimit: BuildCacheConfiguration.SizeLimit?

        @Flag(
            name: .customLong("diagnostic-remarks"),
            inversion: .prefixedEnableDisable,
            help: "Enable or disable diagnostic remarks about build cache hits and misses."
        )
        var diagnosticRemarks: Bool?

        @Option(help: "The path to an LLVM-compatible build cache plugin.", completion: .directory)
        var pluginPath: AbsolutePath?

        @Option(help: "The path to a remote build cache service.", completion: .directory)
        var remoteServicePath: AbsolutePath?

        @Flag(
            name: .customLong("prefix-mapping"),
            inversion: .prefixedEnableDisable,
            help: "Enable or disable prefix mapping, allowing copies of a package at different paths to share cached outputs."
        )
        var prefixMapping: Bool?

        @OptionGroup
        fileprivate var scope: ScopeOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            if self.enabled == nil, self.path == nil, self.sizeLimit == nil, self.diagnosticRemarks == nil,
               self.remoteServicePath == nil, self.pluginPath == nil, self.prefixMapping == nil {
                swiftCommandState.observabilityScope.emit(.error("no configuration options were provided"))
                throw ExitCode.validationFailure
            }

            let config = try getBuildCacheConfig(swiftCommandState)
            try update(config, scope: self.scope) { configuration in
                if let enabled = self.enabled {
                    configuration.enabled = enabled
                }
                if let path = self.path {
                    configuration.casPath = path
                }
                if let sizeLimit = self.sizeLimit {
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

    struct ResetConfiguration: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "reset-configuration",
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

            let enabled = configuration.enabled.map { $0 ? "enabled" : "disabled" } ?? "disabled (default)"
            print("build cache: \(enabled)")

            // The remaining parameters only apply when caching is enabled, and
            // caching is disabled by default.
            if configuration.enabled != true {
                return
            }

            print("path: \(configuration.casPath?.pathString ?? swiftCommandState.defaultBuildCacheDirectory.pathString)")

            switch configuration.sizeLimit {
            case .size(let value):
                print("size limit: \(value)")
            case .percent(let value):
                print("size limit: \(value)% of available disk space")
            case .none:
                print("size limit: default")
            }

            let remarks = configuration.enableDiagnosticRemarks
                .map { $0 ? "enabled" : "disabled" } ?? "disabled (default)"
            print("diagnostic remarks: \(remarks)")

            if let pluginPath = configuration.pluginPath {
                print("plugin path: \(pluginPath.pathString)")
            }

            if let remoteServicePath = configuration.remoteServicePath {
                print("remote service path: \(remoteServicePath.pathString)")
            }

            let prefixMapping = configuration.enablePrefixMapping
                .map { $0 ? "enabled" : "disabled" } ?? "enabled (default)"
            print("prefix mapping: \(prefixMapping)")
        }
    }

    struct Info: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Report information about the build cache."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let configuration = try swiftCommandState.resolveBuildCacheConfiguration()
            let cachePath = configuration.casPath ?? swiftCommandState.defaultBuildCacheDirectory

            guard swiftCommandState.fileSystem.exists(cachePath) else {
                print("No build cache found at \(cachePath.pathString)")
                return
            }

            let info: SWBBuildCacheInfo
            do {
                info = try await queryBuildCacheInfo(
                    casPath: cachePath,
                    pluginPath: configuration.pluginPath,
                    remoteServicePath: configuration.remoteServicePath,
                    toolchain: try swiftCommandState.productsBuildParameters.toolchain,
                    packageManagerResourcesDirectory: swiftCommandState.packageManagerResourcesDirectory
                )
            } catch {
                swiftCommandState.observabilityScope.emit(
                    error: "failed to get build cache info: \(error.interpolationDescription)"
                )
                throw ExitCode.failure
            }

            print("path: \(cachePath.pathString)")
            print("size: \(ByteCountFormatter.string(fromByteCount: Int64(info.onDiskSize), countStyle: .file))")
        }
    }

    struct Clean: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "clean",
            abstract: "Delete the on-disk build cache."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let configuration = try swiftCommandState.resolveBuildCacheConfiguration()
            let cachePath = configuration.casPath ?? swiftCommandState.defaultBuildCacheDirectory

            let fileSystem = swiftCommandState.fileSystem
            guard fileSystem.exists(cachePath) else {
                print("No build cache found at \(cachePath.pathString)")
                return
            }
            try fileSystem.removeFileTree(cachePath)
            print("Cleaned build cache at \(cachePath.pathString)")
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
