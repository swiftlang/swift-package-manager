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
import TSCBasic
import Workspace

extension SwiftPackageTool {
    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manipulate configuration of the package",
            subcommands: [SetMirror.self, UnsetMirror.self, GetMirror.self])
    }
}

extension SwiftPackageTool.Config {
    struct SetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a mirror for a dependency")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The package dependency url")
        var packageURL: String?

        @Option(help: "The original url")
        var originalURL: String?

        @Option(help: "The mirror url")
        var mirrorURL: String

        func run(_ swiftTool: SwiftTool) throws {
            let config = try getMirrorsConfig(swiftTool)

            if self.packageURL != nil {
                swiftTool.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalURL = self.packageURL ?? self.originalURL else {
                swiftTool.observabilityScope.emit(.missingRequiredArg("--original-url"))
                throw ExitCode.failure
            }

            try config.applyLocal { mirrors in
                mirrors.set(mirrorURL: self.mirrorURL, forURL: originalURL)
            }
        }
    }

    struct UnsetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing mirror")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The package dependency url")
        var packageURL: String?

        @Option(help: "The original url")
        var originalURL: String?

        @Option(help: "The mirror url")
        var mirrorURL: String?

        func run(_ swiftTool: SwiftTool) throws {
            let config = try getMirrorsConfig(swiftTool)

            if self.packageURL != nil {
                swiftTool.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalOrMirrorURL = self.packageURL ?? self.originalURL ?? self.mirrorURL else {
                swiftTool.observabilityScope.emit(.missingRequiredArg("--original-url or --mirror-url"))
                throw ExitCode.failure
            }

            try config.applyLocal { mirrors in
                try mirrors.unset(originalOrMirrorURL: originalOrMirrorURL)
            }
        }
    }

    struct GetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print mirror configuration for the given package dependency")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The package dependency url")
        var packageURL: String?

        @Option(help: "The original url")
        var originalURL: String?

        func run(_ swiftTool: SwiftTool) throws {
            let config = try getMirrorsConfig(swiftTool)

            if self.packageURL != nil {
                swiftTool.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalURL = self.packageURL ?? self.originalURL else {
                swiftTool.observabilityScope.emit(.missingRequiredArg("--original-url"))
                throw ExitCode.failure
            }

            if let mirror = config.mirrors.mirrorURL(for: originalURL) {
                print(mirror)
            } else {
                stderrStream <<< "not found\n"
                stderrStream.flush()
                throw ExitCode.failure
            }
        }
    }

    static func getMirrorsConfig(_ swiftTool: SwiftTool) throws -> Workspace.Configuration.Mirrors {
        let workspace = try swiftTool.getActiveWorkspace()
        return try .init(
            fileSystem: swiftTool.fileSystem,
            localMirrorsFile: workspace.location.localMirrorsConfigurationFile,
            sharedMirrorsFile: workspace.location.sharedMirrorsConfigurationFile
        )
    }
}

private extension Basics.Diagnostic {
    static func missingRequiredArg(_ argument: String) -> Self {
        .error("missing required argument \(argument)")
    }
}
