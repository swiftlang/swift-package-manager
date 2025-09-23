
import ArgumentParser
import ArgumentParserToolInfo

import Basics

@_spi(SwiftPMInternal)
import CoreCommands

import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore
import TSCBasic
import TSCUtility
import Workspace

struct TemplatePluginCoordinator {
    let buildSystem: BuildSystemProvider.Kind
    let swiftCommandState: SwiftCommandState
    let scratchDirectory: Basics.AbsolutePath
    let template: String
    let args: [String]
    let branches: [String]

    private let EXPERIMENTAL_DUMP_HELP = ["--", "--experimental-dump-help"]

    func loadPackageGraph() async throws -> ModulesGraph {
        try await self.swiftCommandState.withTemporaryWorkspace(switchingTo: self.scratchDirectory) { _, _ in
            try await self.swiftCommandState.loadPackageGraph()
        }
    }

    /// Loads the plugin that corresponds to the template's name.
    ///
    /// - Throws:
    ///   - `PluginError.noMatchingTemplate(name: String?)` if there are no plugins corresponding to the desired
    /// template.
    ///   - `PluginError.multipleMatchingTemplates(names: [String]` if the search returns more than one plugin given a
    /// desired template
    ///
    /// - Returns: A data representation of the result of the execution of the template's plugin.
    func loadTemplatePlugin(from packageGraph: ModulesGraph) throws -> ResolvedModule {
        let matchingPlugins = PluginCommand.findPlugins(matching: self.template, in: packageGraph, limitedTo: nil)
        switch matchingPlugins.count {
        case 0:
            throw PluginError.noMatchingTemplate(name: self.template)
        case 1:
            return matchingPlugins[0]
        default:
            let names = matchingPlugins.compactMap { plugin in
                (plugin.underlying as? PluginModule)?.capability.commandInvocationVerb
            }
            throw PluginError.multipleMatchingTemplates(names: names)
        }
    }

    /// Manages the logic of dumping the JSON representation of a template's decision tree.
    ///
    /// - Throws:
    ///   - `TemplatePluginError.failedToDecodeToolInfo(underlying: error)` If there is a change in representation
    /// between the JSON and the current version of the ToolInfoV0 struct

    func dumpToolInfo(
        using plugin: ResolvedModule,
        from packageGraph: ModulesGraph,
        rootPackage: ResolvedPackage
    ) async throws -> ToolInfoV0 {
        let output = try await TemplatePluginRunner.run(
            plugin: plugin,
            package: rootPackage,
            packageGraph: packageGraph,
            buildSystem: self.buildSystem,
            arguments: self.EXPERIMENTAL_DUMP_HELP,
            swiftCommandState: self.swiftCommandState,
            requestPermission: true
        )

        do {
            return try JSONDecoder().decode(ToolInfoV0.self, from: output)
        } catch {
            throw PluginError.failedToDecodeToolInfo(underlying: error)
        }
    }

    enum PluginError: Error, CustomStringConvertible {
        case noMatchingTemplate(name: String?)
        case multipleMatchingTemplates(names: [String])
        case failedToDecodeToolInfo(underlying: Error)

        var description: String {
            switch self {
            case .noMatchingTemplate(let name):
                "No templates found matching '\(name ?? "<none>")'"
            case .multipleMatchingTemplates(let names):
                "Multiple templates matched: \(names.joined(separator: ", "))"
            case .failedToDecodeToolInfo(let underlying):
                "Failed to decode tool info: \(underlying.localizedDescription)"
            }
        }
    }
}

extension PluginCapability {
    fileprivate var commandInvocationVerb: String? {
        guard case .command(let intent, _) = self else { return nil }
        return intent.invocationVerb
    }
}
