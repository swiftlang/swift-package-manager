
import ArgumentParser
import ArgumentParserToolInfo

import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import PackageModel
import Workspace
import SPMBuildCore
import TSCBasic
import TSCUtility
import Foundation
import PackageGraph


struct TemplatePluginManager {
    let swiftCommandState: SwiftCommandState
    let template: String?

    let packageGraph: ModulesGraph

    let scratchDirectory: Basics.AbsolutePath

    let args: [String]

    init(swiftCommandState: SwiftCommandState, template: String?, scratchDirectory: Basics.AbsolutePath, args: [String]) async throws {
        self.swiftCommandState = swiftCommandState
        self.template = template
        self.scratchDirectory = scratchDirectory
        self.args = args

        self.packageGraph = try await swiftCommandState.withTemporaryWorkspace(switchingTo: scratchDirectory) { _, _ in
                try await swiftCommandState.loadPackageGraph()
        }
    }
    //revisit for future refactoring
    func run(_ initTemplatePackage: InitTemplatePackage) async throws {

        let commandLinePlugin = try loadTemplatePlugin()

        let output = try await TemplatePluginRunner.run(
            plugin: commandLinePlugin,
            package: self.packageGraph.rootPackages.first!,
            packageGraph: packageGraph,
            arguments: ["--", "--experimental-dump-help"],
            swiftCommandState: swiftCommandState
        )
        let toolInfo = try JSONDecoder().decode(ToolInfoV0.self, from: output)
        let cliResponses = try initTemplatePackage.promptUser(command: toolInfo.command, arguments: args)

        for response in cliResponses {
            _ = try await TemplatePluginRunner.run(
                plugin: commandLinePlugin,
                package: packageGraph.rootPackages.first!,
                packageGraph: packageGraph,
                arguments: response,
                swiftCommandState: swiftCommandState
            )
        }

    }

    private func loadTemplatePlugin() throws -> ResolvedModule {

        let matchingPlugins = PluginCommand.findPlugins(matching: self.template, in: self.packageGraph, limitedTo: nil)

        guard let commandPlugin = matchingPlugins.first else {
            guard let template = template
            else { throw ValidationError("No templates were found in \(packageGraph.rootPackages.first!.path)") } //better error message

            throw ValidationError("No templates were found that match the name \(template)")
        }

        guard matchingPlugins.count == 1 else {
            let templateNames = matchingPlugins.compactMap { module in
                let plugin = module.underlying as! PluginModule
                guard case .command(let intent, _) = plugin.capability else { return String?.none }

                return intent.invocationVerb
            }
            throw ValidationError(
                "More than one template was found in the package. Please use `--type` along with one of the available templates: \(templateNames.joined(separator: ", "))"
            )
        }

        return commandPlugin
    }
}
