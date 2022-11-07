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
import TSCUtility

extension SwiftPackageTool {
    struct ResolveOptions: ParsableArguments {
        @Option(help: "The version to resolve at", transform: { Version($0) })
        var version: Version?

        @Option(help: "The branch to resolve at")
        var branch: String?

        @Option(help: "The revision to resolve at")
        var revision: String?

        @Argument(help: "The name of the package to resolve")
        var packageName: String?
    }

    struct Resolve: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resolve package dependencies")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftTool: SwiftTool) throws {
            // If a package is provided, use that to resolve the dependencies.
            if let packageName = resolveOptions.packageName {
                let workspace = try swiftTool.getActiveWorkspace()
                try workspace.resolve(
                    packageName: packageName,
                    root: swiftTool.getWorkspaceRoot(),
                    version: resolveOptions.version,
                    branch: resolveOptions.branch,
                    revision: resolveOptions.revision,
                    observabilityScope: swiftTool.observabilityScope
                )
                if swiftTool.observabilityScope.errorsReported {
                    throw ExitCode.failure
                }
            } else {
                // Otherwise, run a normal resolve.
                try swiftTool.resolve()
            }
        }
    }

    struct Fetch: SwiftCommand {
        static let configuration = CommandConfiguration(shouldDisplay: false)

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftTool: SwiftTool) throws {
            swiftTool.observabilityScope.emit(warning: "'fetch' command is deprecated; use 'resolve' instead")

            let resolveCommand = Resolve(globalOptions: _globalOptions, resolveOptions: _resolveOptions)
            try resolveCommand.run(swiftTool)
        }
    }
}
