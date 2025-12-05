import ArgumentParserToolInfo

import Basics

import CoreCommands
import Foundation
import PackageGraph
import SPMBuildCore
import Workspace

public protocol TemplatePluginManager {
    func loadTemplatePlugin() throws -> ResolvedModule
}

/// Utility for executing template plugins with common patterns.
enum TemplatePluginExecutor {
    static func execute(
        plugin: ResolvedModule,
        rootPackage: ResolvedPackage,
        packageGraph: ModulesGraph,
        buildSystemKind: BuildSystemProvider.Kind,
        arguments: [String],
        swiftCommandState: SwiftCommandState,
        requestPermission: Bool = false
    ) async throws -> Data {
        try await TemplatePluginRunner.run(
            plugin: plugin,
            package: rootPackage,
            packageGraph: packageGraph,
            buildSystem: buildSystemKind,
            arguments: arguments,
            swiftCommandState: swiftCommandState,
            requestPermission: requestPermission
        )
    }
}

/// A utility for obtaining and running a template's plugin .
///
/// `TemplateInitializationPluginManager` encapsulates the logic needed to fetch,
///  and run templates' plugins given arguments, based on the template initialization workflow.
struct TemplateInitializationPluginManager: TemplatePluginManager {
    private let swiftCommandState: SwiftCommandState
    private let template: String
    private let scratchDirectory: Basics.AbsolutePath
    private let args: [String]
    private let packageGraph: ModulesGraph
    private let coordinator: TemplatePluginCoordinator
    private let buildSystem: BuildSystemProvider.Kind

    private var rootPackage: ResolvedPackage {
        get throws {
            guard let root = packageGraph.rootPackages.first else {
                throw TemplateInitializationError.missingPackageGraph
            }
            return root
        }
    }

    init(
        swiftCommandState: SwiftCommandState,
        template: String,
        scratchDirectory: Basics.AbsolutePath,
        args: [String],
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        let coordinator = TemplatePluginCoordinator(
            buildSystem: buildSystem,
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
        self.buildSystem = buildSystem
    }

    /// Manages the logic of running a template and executing on the information provided by the JSON representation of
    /// a template's arguments.
    ///
    /// - Throws: Any error thrown during the loading of the template plugin, the fetching of the JSON representation of
    /// the template's arguments, prompting, or execution of the template
    func run() async throws {
        let plugin = try loadTemplatePlugin()
        let toolInfo = try await coordinator.dumpToolInfo(
            using: plugin,
            from: self.packageGraph,
            rootPackage: self.rootPackage
        )

        let cliResponses: [String] = try promptUserForTemplateArguments(using: toolInfo)

        _ = try await self.runTemplatePlugin(plugin, with: cliResponses)
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
    private func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [String] {
        return try TemplateCLIConstructor(
            hasTTY: self.swiftCommandState.outputStream.isTTY, observabilityScope: self.swiftCommandState.observabilityScope).createCLIArgs(predefinedArgs: self.args, toolInfoJson: toolInfo)
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
        try await TemplatePluginExecutor.execute(
            plugin: plugin,
            rootPackage: self.rootPackage,
            packageGraph: self.packageGraph,
            buildSystemKind: self.buildSystem,
            arguments: arguments,
            swiftCommandState: self.swiftCommandState,
            requestPermission: false
        )
    }

    /// Loads the plugin that corresponds to the template's name
    ///
    /// - Returns: A data representation of the result of the execution of the template's plugin.
    /// - Throws: Any Errors thrown during the loading of the template's plugin.
    func loadTemplatePlugin() throws -> ResolvedModule {
        try self.coordinator.loadTemplatePlugin(from: self.packageGraph)
    }

    enum TemplateInitializationError: Error, CustomStringConvertible {
        case missingPackageGraph

        var description: String {
            switch self {
            case .missingPackageGraph:
                "No root package was found in package graph."
            }
        }
    }
}
