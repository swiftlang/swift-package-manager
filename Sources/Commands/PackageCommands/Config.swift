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
import PackageGraph
import Workspace

import var TSCBasic.stderrStream

extension SwiftPackageCommand {
    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manipulate configuration of the package",
            subcommands: [SetMirror.self, UnsetMirror.self, GetMirror.self]
        )
    }
}

extension SwiftPackageCommand.Config {
    struct SetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a mirror for a dependency"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(name: .customLong("package-url"), help: .hidden)
        var _deprecate_packageURL: String?

        @Option(name: .customLong("original-url"), help: .hidden)
        var _deprecate_originalURL: String?

        @Option(name: .customLong("mirror-url"), help: .hidden)
        var _deprecate_mirrorURL: String?

        @Option(help: "The original url or identity")
        var original: String?

        @Option(help: "The mirror url or identity")
        var mirror: String?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState)

            if self._deprecate_packageURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original' instead"
                )
            }
            if self._deprecate_originalURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--original-url' option is deprecated; use '--original' instead"
                )
            }
            if self._deprecate_mirrorURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--mirror-url' option is deprecated; use '--mirror' instead"
                )
            }

            guard let original = self._deprecate_packageURL ?? self._deprecate_originalURL ?? self.original else {
                swiftCommandState.observabilityScope.emit(.missingRequiredArg("--original"))
                throw ExitCode.failure
            }

            guard let mirror = self._deprecate_mirrorURL ?? self.mirror else {
                swiftCommandState.observabilityScope.emit(.missingRequiredArg("--mirror"))
                throw ExitCode.failure
            }

            try config.applyLocal { mirrors in
                try mirrors.set(mirror: mirror, for: original)
            }
        }
    }

    struct UnsetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing mirror"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(name: .customLong("package-url"), help: .hidden)
        var _deprecate_packageURL: String?

        @Option(name: .customLong("original-url"), help: .hidden)
        var _deprecate_originalURL: String?

        @Option(name: .customLong("mirror-url"), help: .hidden)
        var _deprecate_mirrorURL: String?

        @Option(help: "The original url or identity")
        var original: String?

        @Option(help: "The mirror url or identity")
        var mirror: String?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState)

            if self._deprecate_packageURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original' instead"
                )
            }
            if self._deprecate_originalURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--original-url' option is deprecated; use '--original' instead"
                )
            }
            if self._deprecate_mirrorURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--mirror-url' option is deprecated; use '--mirror' instead"
                )
            }

            guard let originalOrMirror = self._deprecate_packageURL ?? self._deprecate_originalURL ?? self
                .original ?? self._deprecate_mirrorURL ?? self.mirror
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
            abstract: "Print mirror configuration for the given package dependency"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions
        @Option(name: .customLong("package-url"), help: .hidden)
        var _deprecate_packageURL: String?

        @Option(name: .customLong("original-url"), help: .hidden)
        var _deprecate_originalURL: String?

        @Option(help: "The original url or identity")
        var original: String?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let config = try getMirrorsConfig(swiftCommandState)

            if self._deprecate_packageURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original' instead"
                )
            }
            if self._deprecate_originalURL != nil {
                swiftCommandState.observabilityScope.emit(
                    warning: "'--original-url' option is deprecated; use '--original' instead"
                )
            }

            guard let original = self._deprecate_packageURL ?? self._deprecate_originalURL ?? self.original else {
                swiftCommandState.observabilityScope.emit(.missingRequiredArg("--original"))
                throw ExitCode.failure
            }

            if let mirror = config.mirrors.mirror(for: original) {
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
