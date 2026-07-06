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
import Foundation
import PackageGraph
import Workspace

import var TSCBasic.stderrStream

extension SwiftPackageCommand {
    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manipulate configuration of the package",
            subcommands: [SetMirror.self, UnsetMirror.self, GetMirror.self, SetProxy.self, GetProxy.self, UnsetProxy.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )
    }
}

extension SwiftPackageCommand.Config {
    struct SetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a mirror for a dependency."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The original url or identity.")
        var original: String

        @Option(help: "The mirror url or identity.")
        var mirror: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState)


            try config.applyLocal { mirrors in
                try mirrors.set(mirror: self.mirror, for: self.original)
            }
        }
    }

    struct UnsetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing mirror."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The original url or identity.")
        var original: String?

        @Option(help: "The mirror url or identity.")
        var mirror: String?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState)

            guard let originalOrMirror = self.original ?? self.mirror
            else {
                swiftCommandState.observabilityScope.emit(.missingRequiredArg("--original or --mirror"))
                throw ExitCode.failure
            }

            try config.applyLocal { mirrors in
                try mirrors.unset(originalOrMirror: originalOrMirror)
            }
        }
    }

    struct GetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print mirror configuration for the given package dependency."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The original url or identity.")
        var original: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState)

            if let mirror = config.mirrors.mirror(for: self.original) {
                print(mirror)
            } else {
                stderrStream.send("not found\n")
                stderrStream.flush()
                throw ExitCode.failure
            }
        }
    }

    static func getMirrorsConfig(_ swiftCommandState: SwiftCommandState) throws -> Workspace.Configuration.Mirrors {
        let workspace = try swiftCommandState.getActiveWorkspace()
        return try .init(
            fileSystem: swiftCommandState.fileSystem,
            localMirrorsFile: workspace.location.localMirrorsConfigurationFile,
            sharedMirrorsFile: workspace.location.sharedMirrorsConfigurationFile
        )
    }
}

extension Basics.Diagnostic {
    fileprivate static func missingRequiredArg(_ argument: String) -> Self {
        .error("missing required argument \(argument)")
    }
}

// MARK: - Proxy Commands

extension SwiftPackageCommand.Config {
    struct SetProxy: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set proxy configuration for package manager HTTP operations."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(help: "The HTTP proxy URL (e.g., http://proxy:8080).")
        var http: String?

        @Option(help: "The HTTPS proxy URL (e.g., http://proxy:8080).")
        var https: String?

        @Option(
            parsing: .upToNextOption,
            help: "Hosts that should bypass the proxy (comma-separated or multiple values)."
        )
        var noProxy: [String] = []

        func run(_ swiftCommandState: SwiftCommandState) throws {
            guard http != nil || https != nil || !noProxy.isEmpty else {
                swiftCommandState.observabilityScope.emit(.missingRequiredArg("--http, --https, or --no-proxy"))
                throw ExitCode.failure
            }

            let storage = try getProxyStorage(swiftCommandState)

            // Parse comma-separated noProxy values into individual entries
            let noProxyPatterns: [String]? = noProxy.isEmpty ? nil : noProxy.flatMap {
                $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }

            try storage.set(httpProxy: http, httpsProxy: https, noProxy: noProxyPatterns)
        }
    }

    struct GetProxy: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Display the current proxy configuration."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let storage = try getProxyStorage(swiftCommandState)
            let config = try storage.get()

            if let config, !config.isEmpty {
                let configPath = try getProxyConfigPath(swiftCommandState)
                if let httpProxy = config.http?.proxy {
                    print("HTTP proxy:  \(httpProxy) (user: \(configPath))")
                }
                if let httpsProxy = config.https?.proxy {
                    print("HTTPS proxy: \(httpsProxy) (user: \(configPath))")
                }
                if let noProxy = config.noProxy, !noProxy.isEmpty {
                    print("No proxy:    \(noProxy.joined(separator: ", ")) (user: \(configPath))")
                }
            } else {
                // Check for macOS system proxy
                #if canImport(SystemConfiguration)
                if let systemProxy = Self.querySystemProxy() {
                    if let http = systemProxy.http {
                        print("HTTP proxy:  \(http) (system)")
                    }
                    if let https = systemProxy.https {
                        print("HTTPS proxy: \(https) (system)")
                    }
                    if let noProxy = systemProxy.noProxy, !noProxy.isEmpty {
                        print("No proxy:    \(noProxy) (system)")
                    }
                } else {
                    print("No proxy configuration.")
                }
                #else
                print("No proxy configuration.")
                #endif
            }
        }

        #if canImport(SystemConfiguration)
        private static func querySystemProxy() -> (http: String?, https: String?, noProxy: String?)? {
            // Implemented in step 6
            return nil
        }
        #endif
    }

    struct UnsetProxy: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove proxy configuration."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Remove the HTTP proxy setting.")
        var http: Bool = false

        @Flag(help: "Remove the HTTPS proxy setting.")
        var https: Bool = false

        @Flag(help: "Remove the no-proxy exclusion list.")
        var noProxy: Bool = false

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let storage = try getProxyStorage(swiftCommandState)
            try storage.unset(http: http, https: https, noProxy: noProxy)
        }
    }

    static func getProxyStorage(_ swiftCommandState: SwiftCommandState) throws -> Workspace.Configuration.ProxyStorage {
        let workspace = try swiftCommandState.getActiveWorkspace()
        let proxyFile = workspace.location.sharedProxyConfigurationFile
            ?? workspace.location.localProxyConfigurationFile
        return .init(path: proxyFile, fileSystem: swiftCommandState.fileSystem)
    }

    static func getProxyConfigPath(_ swiftCommandState: SwiftCommandState) throws -> String {
        let workspace = try swiftCommandState.getActiveWorkspace()
        let proxyFile = workspace.location.sharedProxyConfigurationFile
            ?? workspace.location.localProxyConfigurationFile
        return proxyFile.pathString
    }
}
