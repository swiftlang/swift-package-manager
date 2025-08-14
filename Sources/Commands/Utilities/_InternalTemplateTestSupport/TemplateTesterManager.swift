
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

/// A utility for obtaining and running a template's plugin .
///
/// `TemplateTesterPluginManager` encapsulates the logic needed to fetch,
///  and run templates' plugins given arguments, based on the template initialization workflow.
public struct TemplateTesterPluginManager: TemplatePluginManager {
    public let swiftCommandState: SwiftCommandState
    public let template: String?

    public let packageGraph: ModulesGraph

    public let scratchDirectory: Basics.AbsolutePath

    public let args: [String]

    public let EXPERIMENTAL_DUMP_HELP: [String] = ["--", "--experimental-dump-help"]

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
    ///   - `TemplatePluginError.execute`

    func run() async throws -> [CommandPath] {
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
        return try promptUserForTemplateArguments(using: toolInfo)
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
    func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [CommandPath] {
        return try TemplateTestPromptingSystem().generateCommandPaths(rootCommand: toolInfo.command)
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

    public func executeTemplatePlugin(_ plugin: ResolvedModule, with arguments: [String]) async throws -> Data {
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

    public func loadTemplatePlugin() throws -> ResolvedModule {

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



public struct CommandPath {
    public let fullPathKey: String
    public let commandChain: [CommandComponent]
}

public struct CommandComponent {
    let commandName: String
    let arguments: [TemplateTestPromptingSystem.ArgumentResponse]
}



public class TemplateTestPromptingSystem {



    public init() {}
    /// Prompts the user for input based on the given command definition and arguments.
    ///
    /// This method collects responses for a command's arguments by first validating any user-provided
    /// arguments (`arguments`) against the command's defined parameters. Any required arguments that are
    /// missing will be interactively prompted from the user.
    ///
    /// If the command has subcommands, the method will attempt to detect a subcommand from any leftover
    /// arguments. If no subcommand is found, the user is interactively prompted to select one. This process
    /// is recursive: each subcommand is treated as a new command and processed accordingly.
    ///
    /// When building each CLI command line, only arguments defined for the current command level are included—
    /// inherited arguments from previous levels are excluded to avoid duplication.
    ///
    /// - Parameters:
    ///   - command: The top-level or current `CommandInfoV0` to prompt for.
    ///   - arguments: The list of pre-supplied command-line arguments to match against defined arguments.
    ///   - subcommandTrail: An internal list of command names to build the final CLI path (used recursively).
    ///   - inheritedResponses: Argument responses collected from parent commands that should be passed down.
    ///
    /// - Returns: A list of command line invocations (`[[String]]`), each representing a full CLI command.
    ///            Each entry includes only arguments relevant to the specific command or subcommand level.
    ///
    /// - Throws: An error if argument parsing or user prompting fails.



    // resolve arguments at this level
    // append arguments to the current path
    // if subcommands exist, then for each subcommand, pass the function again, where we deepCopy a path
    // if not, then jointhe command names of all the paths, and append CommandPath()

    public func generateCommandPaths(rootCommand: CommandInfoV0) throws -> [CommandPath]  {
        var paths: [CommandPath] = []
        var visitedArgs = Set<ArgumentResponse>()

        try dfs(command: rootCommand, path: [], visitedArgs: &visitedArgs, paths: &paths)

        return paths
    }

    func dfs(command: CommandInfoV0, path: [CommandComponent], visitedArgs: inout Set<TemplateTestPromptingSystem.ArgumentResponse>, paths: inout [CommandPath]) throws{

        let allArgs = try convertArguments(from: command)

        let currentArgs = allArgs.filter { arg in
            !visitedArgs.contains(where: {$0.argument.valueName == arg.valueName})
        }


        var collected: [String: ArgumentResponse] = [:]
        let resolvedArgs = UserPrompter.prompt(for: currentArgs, collected: &collected)

        resolvedArgs.forEach { visitedArgs.insert($0) }

        let currentComponent = CommandComponent(
            commandName: command.commandName, arguments: resolvedArgs
        )

        var newPath = path

        newPath.append(currentComponent)

        if let subcommands = getSubCommand(from: command) {
            for sub in subcommands {
                try dfs(command: sub, path: newPath, visitedArgs: &visitedArgs, paths: &paths)
            }
        } else {
            let fullPathKey = joinCommandNames(newPath)
            let commandPath = CommandPath(
                fullPathKey: fullPathKey, commandChain: newPath
            )

            paths.append(commandPath)
        }

        func joinCommandNames(_ path: [CommandComponent]) -> String {
            path.map { $0.commandName }.joined(separator: "-")
        }


    }




    /// Retrieves the list of subcommands for a given command, excluding common utility commands.
    ///
    /// This method checks whether the given command contains any subcommands. If so, it filters
    /// out the `"help"` subcommand (often auto-generated or reserved), and returns the remaining
    /// subcommands.
    ///
    /// - Parameter command: The `CommandInfoV0` instance representing the current command.
    ///
    /// - Returns: An array of `CommandInfoV0` representing valid subcommands, or `nil` if no subcommands exist.
    func getSubCommand(from command: CommandInfoV0) -> [CommandInfoV0]? {
        guard let subcommands = command.subcommands else { return nil }

        let filteredSubcommands = subcommands.filter { $0.commandName.lowercased() != "help" }

        guard !filteredSubcommands.isEmpty else { return nil }

        return filteredSubcommands
    }

    /// Converts the command information into an array of argument metadata.
    ///
    /// - Parameter command: The command info object.
    /// - Returns: An array of argument info objects.
    /// - Throws: `TemplateError.noArguments` if the command has no arguments.

    func convertArguments(from command: CommandInfoV0) throws -> [ArgumentInfoV0] {
        guard let rawArgs = command.arguments else {
            throw TemplateError.noArguments
        }
        return rawArgs
    }

    /// A helper struct to prompt the user for input values for command arguments.

    public enum UserPrompter {
        /// Prompts the user for input for each argument, handling flags, options, and positional arguments.
        ///
        /// - Parameter arguments: The list of argument metadata to prompt for.
        /// - Returns: An array of `ArgumentResponse` representing the user's input.

        public static func prompt(
            for arguments: [ArgumentInfoV0],
            collected: inout [String: ArgumentResponse]
        ) -> [ArgumentResponse] {
            return arguments
                .filter { $0.valueName != "help" && $0.shouldDisplay }
                .compactMap { arg in
                    let key = arg.preferredName?.name ?? arg.valueName ?? UUID().uuidString

                    if let existing = collected[key] {
                        print("Using previous value for '\(key)': \(existing.values.joined(separator: ", "))")
                        return existing
                    }

                    let defaultText = arg.defaultValue.map { " (default: \($0))" } ?? ""
                    let allValuesText = (arg.allValues?.isEmpty == false) ?
                    " [\(arg.allValues!.joined(separator: ", "))]" : ""
                    let promptMessage = "\(arg.abstract ?? "")\(allValuesText)\(defaultText):"

                    var values: [String] = []

                    switch arg.kind {
                    case .flag:
                        let confirmed = promptForConfirmation(
                            prompt: promptMessage,
                            defaultBehavior: arg.defaultValue?.lowercased() == "true"
                        )
                        values = [confirmed ? "true" : "false"]

                    case .option, .positional:
                        print(promptMessage)

                        if arg.isRepeating {
                            while let input = readLine(), !input.isEmpty {
                                if let allowed = arg.allValues, !allowed.contains(input) {
                                    print("Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))")
                                    continue
                                }
                                values.append(input)
                            }
                            if values.isEmpty, let def = arg.defaultValue {
                                values = [def]
                            }
                        } else {
                            let input = readLine()
                            if let input, !input.isEmpty {
                                if let allowed = arg.allValues, !allowed.contains(input) {
                                    print("Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))")
                                    exit(1)
                                }
                                values = [input]
                            } else if let def = arg.defaultValue {
                                values = [def]
                            } else if arg.isOptional == false {
                                fatalError("Required argument '\(arg.valueName ?? "")' not provided.")
                            }
                        }
                    }

                    let response = ArgumentResponse(argument: arg, values: values)
                    collected[key] = response
                    return response
                }

        }
    }

    /// Prompts the user for a yes/no confirmation.
    ///
    /// - Parameters:
    ///   - prompt: The prompt message to display.
    ///   - defaultBehavior: The default value if the user provides no input.
    /// - Returns: `true` if the user confirmed, otherwise `false`.

    private static func promptForConfirmation(prompt: String, defaultBehavior: Bool?) -> Bool {
        let suffix = defaultBehavior == true ? " [Y/n]" : defaultBehavior == false ? " [y/N]" : " [y/n]"
        print(prompt + suffix, terminator: " ")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return defaultBehavior ?? false
        }

        switch input {
        case "y", "yes": return true
        case "n", "no": return false
        default: return defaultBehavior ?? false
        }
    }

    /// Represents a user's response to an argument prompt.

    public struct ArgumentResponse: Hashable {
        /// The argument metadata.
        let argument: ArgumentInfoV0

        /// The values provided by the user.
        public let values: [String]

        /// Returns the command line fragments representing this argument and its values.
        public var commandLineFragments: [String] {
            guard let name = argument.valueName else {
                return self.values
            }

            switch self.argument.kind {
            case .flag:
                return self.values.first == "true" ? ["--\(name)"] : []
            case .option:
                return self.values.flatMap { ["--\(name)", $0] }
            case .positional:
                return self.values
            }
        }
    }


}

/// An error enum representing various template-related errors.
private enum TemplateError: Swift.Error {
    /// The provided path is invalid or does not exist.
    case invalidPath

    /// A manifest file already exists in the target directory.
    case manifestAlreadyExists

    /// The template has no arguments to prompt for.

    case noArguments
    case invalidArgument(name: String)
    case unexpectedArgument(name: String)
    case unexpectedNamedArgument(name: String)
    case missingValueForOption(name: String)
    case invalidValue(argument: String, invalidValues: [String], allowed: [String])
}

extension TemplateError: CustomStringConvertible {
    /// A readable description of the error
    var description: String {
        switch self {
        case .manifestAlreadyExists:
            "a manifest file already exists in this directory"
        case .invalidPath:
            "Path does not exist, or is invalid."
        case .noArguments:
            "Template has no arguments"
        case .invalidArgument(name: let name):
            "Invalid argument name: \(name)"
        case .unexpectedArgument(name: let name):
            "Unexpected argument: \(name)"
        case .unexpectedNamedArgument(name: let name):
            "Unexpected named argument: \(name)"
        case .missingValueForOption(name: let name):
            "Missing value for option: \(name)"
        case .invalidValue(argument: let argument, invalidValues: let invalidValues, allowed: let allowed):
            "Invalid value \(argument). Valid values are: \(allowed.joined(separator: ", ")). \(invalidValues.isEmpty ? "" : "Also, \(invalidValues.joined(separator: ", ")) are not valid.")"
        }
    }
}



private extension PluginCapability {
    var commandInvocationVerb: String? {
        guard case .command(let intent, _) = self else { return nil }
        return intent.invocationVerb
    }
}

