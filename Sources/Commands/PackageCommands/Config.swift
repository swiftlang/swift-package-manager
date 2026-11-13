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
            subcommands: [
                SetMirror.self,
                UnsetMirror.self,
                GetMirror.self,
                SetAdvisoryDatabase.self,
                UnsetAdvisoryDatabase.self,
                GetAdvisoryDatabase.self,
            ],
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

        @Flag(help: "Apply settings to all projects for this user.")
        var global: Bool = false

        @Option(help: "The original url or identity.")
        var original: String

        @Option(help: "The mirror url or identity.")
        var mirror: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState, global: self.global)
            if self.global {
                try config.applyShared { mirrors in
                    try mirrors.set(mirror: mirror, for: original)
                }
            } else {
                try config.applyLocal { mirrors in
                    try mirrors.set(mirror: mirror, for: original)
                }
            }
        }
    }

    struct UnsetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing mirror."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user.")
        var global: Bool = false

        @Option(help: "The original url or identity.")
        var original: String?

        @Option(help: "The mirror url or identity.")
        var mirror: String?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            guard let originalOrMirror = self.original ?? self.mirror
            else {
                swiftCommandState.observabilityScope.emit(.missingRequiredArg("--original or --mirror"))
                throw ExitCode.failure
            }

            let config = try getMirrorsConfig(swiftCommandState, global: self.global)
            if self.global {
                try config.applyShared { mirrors in
                    try mirrors.unset(originalOrMirror: originalOrMirror)
                }
            } else {
                try config.applyLocal { mirrors in
                    try mirrors.unset(originalOrMirror: originalOrMirror)
                }
            }
        }
    }

    struct GetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print mirror configuration for the given package dependency."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Read only settings applied to all projects for this user.")
        var global: Bool = false

        @Option(help: "The original url or identity.")
        var original: String

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState, global: self.global)

            if let mirror = config.mirrors.mirror(for: self.original) {
                print(mirror)
            } else {
                stderrStream.send("not found\n")
                stderrStream.flush()
                throw ExitCode.failure
            }
        }
    }

    static func getMirrorsConfig(_ swiftCommandState: SwiftCommandState, global: Bool) throws -> Workspace.Configuration.Mirrors {
        if global {
            let sharedMirrorsFile = Workspace.DefaultLocations.mirrorsConfigurationFile(
                at: swiftCommandState.sharedConfigurationDirectory
            )
            // Workspace not needed when working with user-level mirrors config
            return try .init(
                fileSystem: swiftCommandState.fileSystem,
                localMirrorsFile: .none,
                sharedMirrorsFile: sharedMirrorsFile
            )
        }
        let workspace = try swiftCommandState.getActiveWorkspace()
        return try .init(
            fileSystem: swiftCommandState.fileSystem,
            localMirrorsFile: workspace.location.localMirrorsConfigurationFile,
            sharedMirrorsFile: workspace.location.sharedMirrorsConfigurationFile
        )
    }
}

extension SwiftPackageCommand.Config {
    struct SetAdvisoryDatabase: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the advisory database used by 'swift package audit'."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user.")
        var global: Bool = false

        @Argument(help: ArgumentHelp(
            "The URL of an OSV-compatible database: an https:// URL of an OSV API server, or a file:// URL of a directory or ZIP archive of OSV records.",
            valueName: "url"
        ))
        var url: String

        func validate() throws {
            guard let url = URL(string: self.url),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "file"
            else {
                throw ValidationError("invalid advisory database URL '\(self.url)'; use an https:// URL or a file:// URL")
            }
        }

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getAuditConfig(swiftCommandState, global: self.global)
            if self.global {
                try config.updateShared { $0.advisoryDatabase = self.url }
            } else {
                try config.updateLocal { $0.advisoryDatabase = self.url }
            }
        }
    }

    struct UnsetAdvisoryDatabase: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove the configured advisory database used by 'swift package audit'."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Apply settings to all projects for this user.")
        var global: Bool = false

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getAuditConfig(swiftCommandState, global: self.global)
            if self.global {
                try config.updateShared { $0.advisoryDatabase = nil }
            } else {
                try config.updateLocal { $0.advisoryDatabase = nil }
            }
        }
    }

    struct GetAdvisoryDatabase: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the advisory database used by 'swift package audit'.",
            discussion: """
                Prints the package's setting if there is one, otherwise the user's setting, otherwise the default \
                database. With --global, the package's setting is not considered.
                """
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Flag(help: "Read only settings applied to all projects for this user.")
        var global: Bool = false

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getAuditConfig(swiftCommandState, global: self.global)
            print(config.advisoryDatabase ?? SwiftPackageCommand.Audit.defaultAdvisoryDatabase)
        }
    }

    static func getAuditConfig(_ swiftCommandState: SwiftCommandState, global: Bool) throws -> Workspace.Configuration.Audit {
        if global {
            // Workspace not needed when working with user-level audit config
            return try .init(
                fileSystem: swiftCommandState.fileSystem,
                localAuditFile: .none,
                sharedAuditFile: Workspace.DefaultLocations.auditConfigurationFile(
                    at: swiftCommandState.sharedConfigurationDirectory
                )
            )
        }
        let workspace = try swiftCommandState.getActiveWorkspace()
        return try .init(
            fileSystem: swiftCommandState.fileSystem,
            localAuditFile: workspace.location.localAuditConfigurationFile,
            sharedAuditFile: workspace.location.sharedAuditConfigurationFile
        )
    }
}

extension Basics.Diagnostic {
    fileprivate static func missingRequiredArg(_ argument: String) -> Self {
        .error("missing required argument \(argument)")
    }
}
