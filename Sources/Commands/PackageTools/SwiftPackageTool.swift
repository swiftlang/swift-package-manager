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
import SPMBuildCore
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import XCBuildSupport
import Workspace
import Foundation
import PackageModel

import enum TSCUtility.Diagnostics

/// swift-package tool namespace
public struct SwiftPackageTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package",
        _superCommandName: "swift",
        abstract: "Perform operations on Swift packages",
        discussion: "SEE ALSO: swift build, swift run, swift test",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [
            Clean.self,
            PurgeCache.self,
            Reset.self,
            Update.self,
            Describe.self,
            Init.self,
            Format.self,

            APIDiff.self,
            DeprecatedAPIDiff.self,
            DumpSymbolGraph.self,
            DumpPIF.self,
            DumpPackage.self,

            Edit.self,
            Unedit.self,

            Config.self,
            Resolve.self,
            Fetch.self,

            ShowDependencies.self,
            ToolsVersionCommand.self,
            ComputeChecksum.self,
            ArchiveSource.self,
            CompletionTool.self,
            PluginCommand.self,
            
            DefaultCommand.self,
        ]
        + (ProcessInfo.processInfo.environment["SWIFTPM_ENABLE_SNIPPETS"] == "1" ? [Learn.self] : []),
        defaultSubcommand: DefaultCommand.self,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    var globalOptions: GlobalOptions

    public init() {}

    public static var _errorLabel: String { "error" }
}

extension SwiftPackageTool {
    // This command is the default when no other subcommand is passed. It is not shown in the help and is never invoked directly.
    struct DefaultCommand: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: nil,
            shouldDisplay: false)

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var pluginOptions: PluginCommand.PluginOptions

        @Argument(parsing: .unconditionalRemaining)
        var remaining: [String] = []

        func run(_ swiftTool: SwiftTool) throws {
            // See if have a possible plugin command.
            guard let command = remaining.first else {
                print(SwiftPackageTool.helpMessage())
                return
            }
            
            // Check for edge cases and unknown options to match the behavior in the absence of plugins.
            if command.isEmpty {
                throw ValidationError("Unknown argument '\(command)'")
            }
            else if command.starts(with: "-") {
                throw ValidationError("Unknown option '\(command)'")
            }

            // Otherwise see if we can find a plugin.
            
            // We first have to try to resolve the package graph to find any plugins.
            // TODO: Ideally we should only resolve plugin dependencies, if we had a way of distinguishing them.
            let packageGraph = try swiftTool.loadPackageGraph()

            // Otherwise find all plugins that match the command verb.
            swiftTool.observabilityScope.emit(info: "Finding plugin for command '\(command)'")
            let matchingPlugins = PluginCommand.findPlugins(matching: command, in: packageGraph)

            // Complain if we didn't find exactly one. We have to formulate the error message taking into account that this might be a misspelled subcommand.
            if matchingPlugins.isEmpty {
                throw ValidationError("Unknown subcommand or plugin name '\(command)'")
            }
            else if matchingPlugins.count > 1 {
                throw ValidationError("\(matchingPlugins.count) plugins found for '\(command)'")
            }
            
            // At this point we know we found exactly one command plugin, so we run it.
            try PluginCommand.run(
                plugin: matchingPlugins[0],
                package: packageGraph.rootPackages[0],
                packageGraph: packageGraph,
                options: pluginOptions,
                arguments: Array( remaining.dropFirst()),
                swiftTool: swiftTool)
        }
    }
}
