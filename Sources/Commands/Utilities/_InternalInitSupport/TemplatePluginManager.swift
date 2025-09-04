import ArgumentParserToolInfo

import Basics

import CoreCommands

import Workspace
import Foundation
import PackageGraph

public protocol TemplatePluginManager {
    func loadTemplatePlugin() throws -> ResolvedModule
}

/// Utility for executing template plugins with common patterns.
enum TemplatePluginExecutor {
    static func execute(
        plugin: ResolvedModule,
        rootPackage: ResolvedPackage,
        packageGraph: ModulesGraph,
        arguments: [String],
        swiftCommandState: SwiftCommandState,
        requestPermission: Bool = false
    ) async throws -> Data {
        return try await TemplatePluginRunner.run(
            plugin: plugin,
            package: rootPackage,
            packageGraph: packageGraph,
            arguments: arguments,
            swiftCommandState: swiftCommandState,
            requestPermission: requestPermission
        )
    }
}

/// A utility for obtaining and running a template's plugin .
///
/// `TemplateIntiializationPluginManager` encapsulates the logic needed to fetch,
///  and run templates' plugins given arguments, based on the template initialization workflow.
struct TemplateInitializationPluginManager: TemplatePluginManager {
    private let swiftCommandState: SwiftCommandState
    private let template: String?
    private let scratchDirectory: Basics.AbsolutePath
    private let args: [String]
    private let packageGraph: ModulesGraph
    private let coordinator: TemplatePluginCoordinator

    private var rootPackage: ResolvedPackage {
        get throws {
            guard let root = packageGraph.rootPackages.first else {
                throw TemplateInitializationError.missingPackageGraph
            }
            return root
        }
    }

    init(swiftCommandState: SwiftCommandState, template: String?, scratchDirectory: Basics.AbsolutePath, args: [String]) async throws {
        let coordinator = TemplatePluginCoordinator(
            swiftCommandState: swiftCommandState,
            scratchDirectory: scratchDirectory,
            template: template,
            args: args,
            branches: []
        )

        self.packageGraph = try await coordinator.loadPackageGraph()
        self.swiftCommandState = swiftCommandState
        self.template = template
        self.scratchDirectory = scratchDirectory
        self.args = args
        self.coordinator = coordinator
    }

    /// Manages the logic of running a template and executing on the information provided by the JSON representation of a template's arguments.
    ///
    /// - Throws:
    ///   - `TemplatePluginError.executionFailed(underlying: error)` If there was an error during the execution of a template's plugin.
    ///   - `TemplatePluginError.failedToDecodeToolInfo(underlying: error)` If there is a change in representation between the JSON and the current version of the ToolInfoV0 struct
    ///   - `TemplatePluginError.execu`

    func run() async throws {
        let plugin = try loadTemplatePlugin()
        let toolInfo = try await coordinator.dumpToolInfo(using: plugin, from: packageGraph, rootPackage: rootPackage)

        let cliResponses: [[String]] = try promptUserForTemplateArguments(using: toolInfo)

        for response in cliResponses {
            _ = try await runTemplatePlugin(plugin, with: response)
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
    /// - Parameter toolInfo: The JSON representation of the template's decision tree
    /// - Returns: A 2D array of arguments provided by the user for template generation
    /// - Throws: Any errors during user prompting
    private func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [[String]] {
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

    private func runTemplatePlugin(_ plugin: ResolvedModule, with arguments: [String]) async throws -> Data {
        return try await TemplatePluginExecutor.execute(
            plugin: plugin,
            rootPackage: rootPackage,
            packageGraph: packageGraph,
            arguments: arguments,
            swiftCommandState: swiftCommandState,
            requestPermission: false
        )
    }

    /// Loads the plugin that corresponds to the template's name.
    ///
    /// - Throws:
    ///   - `TempaltePluginError.noMatchingTemplate(name: String?)` if there are no plugins corresponding to the desired template.
    ///   - `TemplatePluginError.multipleMatchingTemplates(names: [String]` if the search returns more than one plugin given a desired template
    ///
    /// - Returns: A data representation of the result of the execution of the template's plugin.

    func loadTemplatePlugin() throws -> ResolvedModule {
        return try coordinator.loadTemplatePlugin(from: packageGraph)
    }

    enum TemplateInitializationError: Error, CustomStringConvertible {
        case missingPackageGraph

        var description: String {
            switch self {
            case .missingPackageGraph:
                return "No root package was found in package graph."
            }
        }
    }

}
