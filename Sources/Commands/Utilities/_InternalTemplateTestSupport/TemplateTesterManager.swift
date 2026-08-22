//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParserToolInfo

import Basics
import CoreCommands
import Foundation
import PackageGraph
import SPMBuildCore
import Workspace

/// A utility for obtaining and running a template's plugin during testing workflows.
///
/// `TemplateTesterPluginManager` encapsulates the logic needed to fetch, load, and execute
/// template plugins with specified arguments. It manages the complete testing workflow including
/// package graph loading, plugin coordination, and command path generation based on user input
/// and branch specifications.
///
/// ## Overview
///
/// The template tester manager handles:
/// - Loading and parsing package graphs for template projects
/// - Coordinating template plugin execution through ``TemplateTester``
/// - Managing the interaction between template plugins and the testing infrastructure
///
/// - Note: This manager is designed specifically for testing workflows and should not be used
///   in production template initialization scenarios.
public struct TemplateTesterPluginManager: TemplatePluginManager {
    /// The Swift command state containing build configuration and observability scope.
    private let swiftCommandState: SwiftCommandState

    /// The name of the template to test. If nil, will be auto-detected from the package manifest.
    private let template: String?

    /// The loaded package graph containing all resolved packages and dependencies.
    private let packageGraph: ModulesGraph

    /// The branch names used to filter which command paths to generate during testing.
    private let branches: [String]

    /// The coordinator responsible for managing template plugin operations.
    private let coordinator: TemplatePluginCoordinator

    /// Whether ``TemplateTesterPluginManager`` generates a JSON file containing predetermined template arguments.
    private let generateArgsFile: Bool

    /// The runtime context when testing templates.
    private let templateTesterContext: TemplateTesterContext

    /// Configuration file for testing templates.
    private let args: AbsolutePath?

    /// The root package from the loaded package graph.
    ///
    /// - Returns: The first root package in the package graph.
    /// - Precondition: The package graph must contain at least one root package.
    /// - Warning: This property will cause a fatal error if no root package is found.
    private var rootPackage: ResolvedPackage {
        guard let root = packageGraph.rootPackages.first else {
            fatalError("No root package found in the package graph. Ensure the template package is properly configured."
            )
        }
        return root
    }

    /// Initializes a new template tester plugin manager.
    ///
    /// This initializer performs the complete setup required for template testing, including
    /// loading the package graph and setting up the plugin coordinator.
    ///
    /// - Parameters:
    ///   - template: The name of the template to test. If not provided, will be auto-detected.
    ///   - branches: The branch names to filter command path generation.
    ///   - generateArgsFile: Boolean determining whether generate a configuration file for templates or not.
    ///   - templateTesterContext: The runtime context when testing templates.
    ///   - args: Configuration file defining arguments to use when running the template.
    ///
    /// - Throws:
    ///   - `PackageGraphError` if the package graph cannot be loaded
    ///   - `TemplatePluginError` if the plugin coordinator setup fails
    init(
        template: String,
        branches: [String],
        generateArgsFile: Bool,
        templateTesterContext: TemplateTesterContext,
        args: AbsolutePath?
    ) async throws {
        let coordinator = TemplatePluginCoordinator(
            buildSystem: templateTesterContext.buildSystem,
            swiftCommandState: templateTesterContext.swiftCommandState,
            scratchDirectory: templateTesterContext.cwd,
            template: template,
            branches: branches
        )

        self.templateTesterContext = templateTesterContext
        self.packageGraph = try await coordinator.loadPackageGraph()
        self.swiftCommandState = templateTesterContext.swiftCommandState
        self.template = template
        self.coordinator = coordinator
        self.branches = branches
        self.generateArgsFile = generateArgsFile
        self.args = args
    }

    /// Executes the template testing workflow.
    ///
    /// This method performs the complete template testing process:
    ///
    /// 1. Loads the template plugin from the package graph.
    /// 2. If an arguments file is provided:
    ///    - Loads template command paths from the file.
    ///    - Executes template tests using those command paths.
    /// 3. Otherwise:
    ///    - Dumps tool information to discover available commands and arguments.
    ///    - Generates all possible command branches from the tool information.
    ///    - Filters the branches based on user configuration.
    ///    - Prompts the user for template arguments for each selected command path.
    ///    - Either generates an arguments file or executes template tests directly.
    ///
    /// - Throws:
    ///   - `TemplatePluginError` if the template plugin cannot be loaded.
    ///   - `ToolInfoError` if tool information cannot be extracted.
    ///   - `TemplateError` if prompting for template arguments fails.
    ///   - Any error thrown while loading arguments or executing template tests.
    public func run() async throws {
        let plugin = try coordinator.loadTemplatePlugin(from: self.packageGraph)

        if let argsFilePath = self.args {
            let templateCommandPaths = try loadArgsFile(from: argsFilePath.asURL)

            try await TemplateTester(
                commandPlugin: plugin,
                templateTesterContext: self.templateTesterContext
            ).testTemplateWith(templateCommandPaths: templateCommandPaths)
        } else {
            let toolInfo = try await coordinator.dumpToolInfo(
                using: plugin,
                from: self.packageGraph,
                rootPackage: self.rootPackage
            )

            let allPaths = try getAllBranches(from: toolInfo)

            var templateCommandPaths: [String: [String]] = [:]

            let filteredPaths = self.filterBranches(branches: self.branches, allPaths: allPaths)

            for path in filteredPaths {
                templateCommandPaths[path.joined(separator: "-")] = try self.promptUserForTemplateArguments(
                    using: toolInfo,
                    arguments: Array(path.dropFirst())
                )
            }

            if self.generateArgsFile {
                self.generateArgsFile(templateCommandPaths)
            } else {
                try await TemplateTester(commandPlugin: plugin, templateTesterContext: self.templateTesterContext)
                    .testTemplateWith(templateCommandPaths: templateCommandPaths)
            }
        }
    }

    // MARK: - JSON loading

    private func loadArgsFile(from jsonPath: URL) throws -> [String: [String]] {
        let data = try Data(contentsOf: jsonPath)
        let decoder = JSONDecoder()
        return try decoder.decode([String: [String]].self, from: data)
    }

    // MARK: - JSON generation

    private func generateArgsFile(_ templateCommandPaths: [String: [String]]) {
        let outputDirectory = self.templateTesterContext.outputDirectory
        let outputFile = outputDirectory.appending(component: "template-args.json")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: templateCommandPaths, options: [.prettyPrinted])
            try jsonData.write(to: outputFile.asURL, options: [.atomic])
            self.swiftCommandState.observabilityScope
                .emit(debug: "JSON file successfully written to \(outputFile.pathString)")
        } catch {
            self.swiftCommandState.observabilityScope
                .emit(debug: "Failed to write JSON file to \(outputFile.pathString): \(error.localizedDescription)")
        }
    }

    // MARK: - Command tree traversal

    private func getAllBranches(from toolInfo: ToolInfoV0) throws -> [[String]] {
        let root = toolInfo.command
        return self.dfs(root, path: [])
    }

    private func dfs(_ command: CommandInfoV0, path: [String]) -> [[String]] {
        let newPath = path + [command.commandName]

        guard let subcommands = TemplateCommandParser.getSubCommand(from: command) else {
            return [newPath]
        }

        var results: [[String]] = []

        for subcommand in subcommands {
            let subResults = self.dfs(subcommand, path: newPath)
            results.append(contentsOf: subResults)
        }
        return results
    }

    // MARK: - Branch filtering

    private func filterBranches(branches: [String], allPaths: [[String]]) -> [[String]] {
        allPaths.filter { path in
            path.starts(with: branches)
        }
    }

    /// Prompts the user for template arguments and generates command paths.
    ///
    /// Uses a `TemplateCLIConstructor` instance to generate command paths
    /// based on the provided tool information and user arguments.
    ///
    /// - Parameters:
    ///   - toolInfo: The tool information extracted from the template plugin.
    ///   - predefinedArgs: Set of predetermined arguments.
    /// - Returns: An array of `String` representing different argument combinations.
    /// - Throws: `TemplateError` if argument parsing or command line generation fails.
    private func promptUserForTemplateArguments(using toolInfo: ToolInfoV0, arguments: [String]) throws -> [String] {
        try TemplateCLIConstructor(
            hasTTY: self.swiftCommandState.outputStream.isTTY,
            observabilityScope: self.swiftCommandState.observabilityScope
        ).createCLIArgs(predefinedArgs: arguments, toolInfoJson: toolInfo)
    }

    /// Loads the template plugin module from the package graph.
    ///
    /// This method delegates to the ``TemplatePluginCoordinator`` to load the actual
    /// plugin module that can be executed during template testing.
    ///
    /// - Returns: A ``ResolvedModule`` representing the loaded template plugin.
    /// - Throws: `TemplatePluginError` if the plugin cannot be found or loaded.
    ///
    /// - Note: This method should be called after the package graph has been successfully loaded.
    public func loadTemplatePlugin() throws -> ResolvedModule {
        try self.coordinator.loadTemplatePlugin(from: self.packageGraph)
    }
}
