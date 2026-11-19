//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
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
import PackageModel
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax
import TSCBasic
import TSCUtility
import Workspace

extension SwiftPackageCommand {
    struct AddTargetPlugin: SwiftCommand {
        package static let configuration = CommandConfiguration(
            abstract: "Add a new target plugin to the manifest"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "The name of the new plugin")
        var pluginName: String

        @Argument(help: "The name of the target to update")
        var targetName: String

        @Option(help: "The package in which the plugin resides")
        var package: String?

        func run(_ swiftCommandState: SwiftCommandState) throws {
            let (manifestSyntax, manifestPath) = try swiftCommandState.readPackageManifestAsSyntaxTree()

            let pluginUsage: PackageTarget.PluginUsage = .plugin(name: pluginName, package: package)

            let editResult = try SwiftRefactor.AddPluginUsage.textRefactor(
                syntax: manifestSyntax,
                in: .init(
                    targetName: targetName,
                    pluginUsage: pluginUsage
                )
            )

            try editResult.applyEdits(
                to: swiftCommandState.getActiveWorkspace().fileSystem,
                manifest: manifestSyntax,
                manifestPath: manifestPath,
                verbose: !globalOptions.logging.quiet
            )
        }
    }
}
