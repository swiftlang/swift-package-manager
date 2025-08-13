
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

public protocol TemplatePluginManager {
    func run() async throws
    func loadTemplatePlugin() throws -> ResolvedModule
    func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [[String]]
    func executeTemplatePlugin(_ plugin: ResolvedModule, with arguments: [String]) async throws -> Data

    var swiftCommandState: SwiftCommandState { get }
    var template: String? { get }
    var packageGraph: ModulesGraph { get }
    var scratchDirectory: Basics.AbsolutePath { get }
    var args: [String] { get }

    var EXPERIMENTAL_DUMP_HELP: [String] { get }
}


/// A utility for obtaining and running a template's plugin .
///
/// `TemplateIntiializationPluginManager` encapsulates the logic needed to fetch,
///  and run templates' plugins given arguments, based on the template initialization workflow.
struct TemplateInitializationPluginManager: TemplatePluginManager {
    let swiftCommandState: SwiftCommandState
    let template: String?

    let packageGraph: ModulesGraph

    let scratchDirectory: Basics.AbsolutePath

    let args: [String]

    let EXPERIMENTAL_DUMP_HELP: [String] = ["--", "--experimental-dump-help"]

    var rootPackage: ResolvedPackage {
        guard let root = packageGraph.rootPackages.first else {
            fatalError("No root package found in the package graph.")
        }
        return root
    }

    init(swiftCommandState: SwiftCommandState, template: String?, scratchDirectory: Basics.AbsolutePath, args: [String]) async throws {
        self.swiftCommandState = swiftCommandState
        self.template = template
        self.scratchDirectory = scratchDirectory
        self.args = args

        self.packageGraph = try await swiftCommandState.withTemporaryWorkspace(switchingTo: scratchDirectory) { _, _ in
                try await swiftCommandState.loadPackageGraph()
        }
    }

    /// Manages the logic of running a template and executing on the information provided by the JSON representation of a template's arguments.
    ///
    /// - Throws:
    ///   - `TemplatePluginError.executionFailed(underlying: error)` If there was an error during the execution of a template's plugin.
    ///   - `TemplatePluginError.failedToDecodeToolInfo(underlying: error)` If there is a change in representation between the JSON and the current version of the ToolInfoV0 struct
    ///   - `TemplatePluginError.execu`

    func run() async throws {
        //Load the plugin corresponding to the template
        let commandLinePlugin = try loadTemplatePlugin()

        // Execute experimental-dump-help to get the JSON representing the template's decision tree
        let output: Data

        do {
            output = try await executeTemplatePlugin(commandLinePlugin, with: EXPERIMENTAL_DUMP_HELP)
        } catch {
            throw TemplatePluginError.executionFailed(underlying: error)
        }

        //Decode the JSON into ArgumentParserToolInfo ToolInfoV0 struct
        let toolInfo: ToolInfoV0

        do {
            toolInfo = try JSONDecoder().decode(ToolInfoV0.self, from: output)
        } catch {
            throw TemplatePluginError.failedToDecodeToolInfo(underlying: error)
        }

        // Prompt the user for any information needed by the template
        let cliResponses: [[String]] = try promptUserForTemplateArguments(using: toolInfo)

        // Execute the template to generate a user's project
        for response in cliResponses {
            do {
                let _ = try await executeTemplatePlugin(commandLinePlugin, with: response)
            } catch {
                throw TemplatePluginError.executionFailed(underlying: error)
            }
        }
    }

    /// Utilizes the prompting system defined by the struct to prompt user.
    ///
    /// - Parameters:
    ///   - toolInfo: The JSON representation of the template's decision tree.
    ///
    /// - Throws:
    ///   - Any other errors thrown during the prompting of the user.
    ///
    /// - Returns: A 2D array of the arguments given by the user, that will be consumed by the template during the project generation phase.
    func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [[String]] {
        return try TemplatePromptingSystem().promptUser(command: toolInfo.command, arguments: args)
    }


    /// Runs the plugin of a template given a set of arguments.
    ///
    /// - Parameters:
    ///   - plugin: The resolved module that corresponds to the plugin tied with the template executable.
    ///   - arguments: A 2D array of arguments that will be passed to the plugin
    ///
    /// - Throws:
    ///   - Any Errors thrown during the execution of the template's plugin given a 2D of arguments.
    ///
    /// - Returns: A data representation of the result of the execution of the template's plugin.

    func executeTemplatePlugin(_ plugin: ResolvedModule, with arguments: [String]) async throws -> Data {
        return try await TemplatePluginRunner.run(
            plugin: plugin,
            package: rootPackage,
            packageGraph: packageGraph,
            arguments: arguments,
            swiftCommandState: swiftCommandState
        )
    }

    /// Loads the plugin that corresponds to the template's name.
    ///
    /// - Throws:
    ///   - `TempaltePluginError.noMatchingTemplate(name: String?)` if there are no plugins corresponding to the desired template.
    ///   - `TemplatePluginError.multipleMatchingTemplates(names: [String]` if the search returns more than one plugin given a desired template
    ///
    /// - Returns: A data representation of the result of the execution of the template's plugin.

    internal func loadTemplatePlugin() throws -> ResolvedModule {
        let matchingPlugins = PluginCommand.findPlugins(matching: self.template, in: self.packageGraph, limitedTo: nil)

        switch matchingPlugins.count {
        case 0:
            throw TemplatePluginError.noMatchingTemplate(name: self.template)
        case 1:
            return matchingPlugins[0]
        default:
            let names = matchingPlugins.compactMap { plugin in
                (plugin.underlying as? PluginModule)?.capability.commandInvocationVerb
            }
            throw TemplatePluginError.multipleMatchingTemplates(names: names)
        }
    }

    enum TemplatePluginError: Error, CustomStringConvertible {
        case noRootPackage
        case noMatchingTemplate(name: String?)
        case multipleMatchingTemplates(names: [String])
        case failedToDecodeToolInfo(underlying: Error)
        case executionFailed(underlying: Error)

        var description: String {
            switch self {
            case .noRootPackage:
                return "No root package found in the package graph."
            case let .noMatchingTemplate(name):
                let templateName = name ?? "<none>"
                return "No templates found matching '\(templateName)"
            case let .multipleMatchingTemplates(names):
                return """
                Multiple templates matched. Use `--type` to specify one of the following: \(names.joined(separator: ", "))
                """
            case let .failedToDecodeToolInfo(underlying):
                return "Failed to decode template tool info: \(underlying.localizedDescription)"
            case let .executionFailed(underlying):
                return "Plugin execution failed: \(underlying.localizedDescription)"
            }
        }
    }
}

private extension PluginCapability {
    var commandInvocationVerb: String? {
        guard case .command(let intent, _) = self else { return nil }
        return intent.invocationVerb
    }
}



//struct TemplateTestingPluginManager: TemplatePluginManager
