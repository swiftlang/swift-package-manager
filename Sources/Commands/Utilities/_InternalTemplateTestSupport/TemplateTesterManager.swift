import ArgumentParserToolInfo

import Basics

import CoreCommands

import Workspace
import Foundation
import PackageGraph

/// A utility for obtaining and running a template's plugin .
///
/// `TemplateTesterPluginManager` encapsulates the logic needed to fetch,
///  and run templates' plugins given arguments, based on the template initialization workflow.
public struct TemplateTesterPluginManager: TemplatePluginManager {
    public let swiftCommandState: SwiftCommandState
    public let template: String?
    public let scratchDirectory: Basics.AbsolutePath
    public let args: [String]
    public let packageGraph: ModulesGraph
    let coordinator: TemplatePluginCoordinator

    public var rootPackage: ResolvedPackage {
        guard let root = packageGraph.rootPackages.first else {
            fatalError("No root package found.")
        }
        return root
    }

    init(swiftCommandState: SwiftCommandState, template: String?, scratchDirectory: Basics.AbsolutePath, args: [String]) async throws {
        let coordinator = TemplatePluginCoordinator(
            swiftCommandState: swiftCommandState,
            scratchDirectory: scratchDirectory,
            template: template,
            args: args
        )

        self.packageGraph = try await coordinator.loadPackageGraph()
        self.swiftCommandState = swiftCommandState
        self.template = template
        self.scratchDirectory = scratchDirectory
        self.args = args
        self.coordinator = coordinator
    }

    func run() async throws -> [CommandPath] {
        let plugin = try coordinator.loadTemplatePlugin(from: packageGraph)
        let toolInfo = try await coordinator.dumpToolInfo(using: plugin, from: packageGraph, rootPackage: rootPackage)

        return try promptUserForTemplateArguments(using: toolInfo)
    }

    func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [CommandPath] {
        try TemplateTestPromptingSystem().generateCommandPaths(rootCommand: toolInfo.command, args: args)
    }

    public func executeTemplatePlugin(_ plugin: ResolvedModule, with arguments: [String]) async throws -> Data {
        try await TemplatePluginRunner.run(
            plugin: plugin,
            package: rootPackage,
            packageGraph: packageGraph,
            arguments: arguments,
            swiftCommandState: swiftCommandState
        )
    }

    public func loadTemplatePlugin() throws -> ResolvedModule {
        try coordinator.loadTemplatePlugin(from: packageGraph)
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

extension CommandPath {
    func displayFormat() -> String {
        let commandNames = commandChain.map { $0.commandName }
        let fullPath = commandNames.joined(separator: " ")

        var result = "Command Path: \(fullPath) \nExecution Steps: \n\n"

        // Build progressive commands
        for i in 0..<commandChain.count {
            let currentPath = Array(commandNames[0...i]).joined(separator: " ")

            // Only add arguments from the final (current) command component
            let currentComponent = commandChain[i]
            let args = formatArguments(currentComponent.arguments)

            if args.isEmpty {
                result += "\(currentPath)\n"
            } else {
                result += "\(currentPath) \\\n\(args)\n"
            }

            if i < commandChain.count - 1 {
                result += "\n"
            }
        }

        result += "\n\n"
        return result
    }

    private func formatArguments(_ argumentResponses:
                                 [Commands.TemplateTestPromptingSystem.ArgumentResponse]) -> String {
        let formattedArgs = argumentResponses.compactMap { response ->
            String? in
            guard let preferredName =
                    response.argument.preferredName?.name else { return nil }

            let values = response.values.joined(separator: " ")
            return values.isEmpty ? nil : "  --\(preferredName) \(values)"
        }

        return formattedArgs.joined(separator: " \\\n")
    }
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

    private func parseAndMatchArguments(_ input: [String], definedArgs: [ArgumentInfoV0]) throws -> (Set<ArgumentResponse>, [String]) {
        var responses = Set<ArgumentResponse>()
        var providedMap: [String: [String]] = [:]

        var leftover: [String] = []

        var index = 0

        while index < input.count {
            let token = input[index]

            if token.starts(with: "--") {
                let name = String(token.dropFirst(2))

                guard let arg = definedArgs.first(where : {$0.valueName == name}) else {
                    // Unknown — defer for potential subcommand
                    leftover.append(token)
                    index += 1
                    if index < input.count && !input[index].starts(with: "--") {
                        leftover.append(input[index])
                        index += 1
                    }
                    continue
                }

                switch arg.kind {
                case .flag:
                    providedMap[name] = ["true"]
                case .option:
                    index += 1
                    guard index < input.count else {
                        throw TemplateError.missingValueForOption(name: name)
                    }
                    providedMap[name] = [input[index]]
                default:
                    throw TemplateError.unexpectedNamedArgument(name: name)
                }
            } else {
                leftover.append(token)
            }
            index += 1

        }

        for arg in definedArgs {
            let name = arg.valueName ?? "__positional"

            guard let values = providedMap[name] else {continue}

            if let allowed = arg.allValues {
                let invalid = values.filter {!allowed.contains($0)}

                if !invalid.isEmpty {
                    throw TemplateError.invalidValue(
                        argument: name,
                        invalidValues: invalid,
                        allowed: allowed
                    )

                }
            }
            responses.insert(ArgumentResponse(argument: arg, values: values))
            providedMap[name] = nil

        }

        return (responses, leftover)

    }

    public func generateCommandPaths(rootCommand: CommandInfoV0, args: [String]) throws -> [CommandPath]  {
        var paths: [CommandPath] = []
        var visitedArgs = Set<ArgumentResponse>()

        try dfs(command: rootCommand, path: [], visitedArgs: &visitedArgs, paths: &paths, predefinedArgs: args)

        return paths
    }

    func dfs(command: CommandInfoV0, path: [CommandComponent], visitedArgs: inout Set<TemplateTestPromptingSystem.ArgumentResponse>, paths: inout [CommandPath], predefinedArgs: [String]) throws{

        let allArgs = try convertArguments(from: command)

        var currentPredefinedArgs = predefinedArgs

        let (answeredArgs, leftoverArgs) = try
          parseAndMatchArguments(currentPredefinedArgs, definedArgs: allArgs)

        visitedArgs.formUnion(answeredArgs)

        // Separate args into already answered and new ones
        var finalArgs: [TemplateTestPromptingSystem.ArgumentResponse] = []
        var newArgs: [ArgumentInfoV0] = []
        
        for arg in allArgs {
            if let existingArg = visitedArgs.first(where: { $0.argument.valueName == arg.valueName }) {
                // Reuse the previously answered argument
                finalArgs.append(existingArg)
            } else {
                // This is a new argument that needs prompting
                newArgs.append(arg)
            }
        }

        // Only prompt for new arguments
        var collected: [String: ArgumentResponse] = [:]
        let newResolvedArgs = UserPrompter.prompt(for: newArgs, collected: &collected)

        // Add new arguments to final list and visited set
        finalArgs.append(contentsOf: newResolvedArgs)
        newResolvedArgs.forEach { visitedArgs.insert($0) }

        let currentComponent = CommandComponent(
            commandName: command.commandName, arguments: finalArgs
        )

        var newPath = path

        newPath.append(currentComponent)

        if let subcommands = getSubCommand(from: command) {
            for sub in subcommands {
                try dfs(command: sub, path: newPath, visitedArgs: &visitedArgs, paths: &paths, predefinedArgs: leftoverArgs)
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
    case unexpectedSubcommand(name: String)
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
        case .unexpectedSubcommand(name: let name):
            "Invalid subcommand \(name) provided in arguments, arguments only accepts flags, options, or positional arguments. Subcommands are treated via the --branch option"
        }
    }
}
