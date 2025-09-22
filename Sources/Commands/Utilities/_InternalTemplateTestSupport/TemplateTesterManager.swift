import ArgumentParserToolInfo

import Basics
import CoreCommands
import Foundation
import PackageGraph
import SPMBuildCore
import Workspace

/// A utility for obtaining and running a template's plugin .
///
/// `TemplateTesterPluginManager` encapsulates the logic needed to fetch,
///  and run templates' plugins given arguments, based on the template initialization workflow.
public struct TemplateTesterPluginManager: TemplatePluginManager {
    private let swiftCommandState: SwiftCommandState
    private let template: String?
    private let scratchDirectory: Basics.AbsolutePath
    private let args: [String]
    private let packageGraph: ModulesGraph
    private let branches: [String]
    private let coordinator: TemplatePluginCoordinator
    private let buildSystem: BuildSystemProvider.Kind

    private var rootPackage: ResolvedPackage {
        guard let root = packageGraph.rootPackages.first else {
            fatalError("No root package found.")
        }
        return root
    }

    init(
        swiftCommandState: SwiftCommandState,
        template: String?,
        scratchDirectory: Basics.AbsolutePath,
        args: [String],
        branches: [String],
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        let coordinator = TemplatePluginCoordinator(
            buildSystem: buildSystem,
            swiftCommandState: swiftCommandState,
            scratchDirectory: scratchDirectory,
            template: template,
            args: args,
            branches: branches
        )

        self.packageGraph = try await coordinator.loadPackageGraph()
        self.swiftCommandState = swiftCommandState
        self.template = template
        self.scratchDirectory = scratchDirectory
        self.args = args
        self.coordinator = coordinator
        self.branches = branches
        self.buildSystem = buildSystem
    }

    func run() async throws -> [CommandPath] {
        let plugin = try coordinator.loadTemplatePlugin(from: self.packageGraph)
        let toolInfo = try await coordinator.dumpToolInfo(
            using: plugin,
            from: self.packageGraph,
            rootPackage: self.rootPackage
        )

        return try self.promptUserForTemplateArguments(using: toolInfo)
    }

    private func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [CommandPath] {
        try TemplateTestPromptingSystem(hasTTY: self.swiftCommandState.outputStream.isTTY).generateCommandPaths(
            rootCommand: toolInfo.command,
            args: self.args,
            branches: self.branches
        )
    }

    public func loadTemplatePlugin() throws -> ResolvedModule {
        try self.coordinator.loadTemplatePlugin(from: self.packageGraph)
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
        let commandNames = self.commandChain.map(\.commandName)
        let fullPath = commandNames.joined(separator: " ")

        var result = "Command Path: \(fullPath) \nExecution Format: \n\n"

        // Build flat command format: [Command command-args sub-command sub-command-args ...]
        let flatCommand = self.buildFlatCommandDisplay()
        result += "\(flatCommand)\n\n"

        return result
    }

    private func buildFlatCommandDisplay() -> String {
        var result: [String] = []

        for (index, command) in self.commandChain.enumerated() {
            // Add command name (skip the first command name as it's the root)
            if index > 0 {
                result.append(command.commandName)
            }

            // Add all arguments for this command level
            let commandArgs = command.arguments.flatMap(\.commandLineFragments)
            result.append(contentsOf: commandArgs)
        }

        return result.joined(separator: " ")
    }

    private func formatArguments(_ argumentResponses:
        [Commands.TemplateTestPromptingSystem.ArgumentResponse]
    ) -> String {
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
    private let hasTTY: Bool

    public init(hasTTY: Bool = true) {
        self.hasTTY = hasTTY
    }

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
    /// - Returns: A list of command paths, each representing a full CLI command path with arguments.
    ///
    /// - Throws: An error if argument parsing or user prompting fails.

    // resolve arguments at this level
    // append arguments to the current path
    // if subcommands exist, then for each subcommand, pass the function again, where we deepCopy a path
    // if not, then jointhe command names of all the paths, and append CommandPath()

    private func parseAndMatchArguments(
        _ input: [String],
        definedArgs: [ArgumentInfoV0],
        subcommands: [CommandInfoV0] = []
    ) throws -> (Set<ArgumentResponse>, [String]) {
        var responses = Set<ArgumentResponse>()
        var providedMap: [String: [String]] = [:]
        var leftover: [String] = []
        var tokens = input
        var terminatorSeen = false
        var postTerminatorArgs: [String] = []

        let subcommandNames = Set(subcommands.map(\.commandName))
        let positionalArgs = definedArgs.filter { $0.kind == .positional }

        // Handle terminator (--) for post-terminator parsing
        if let terminatorIndex = tokens.firstIndex(of: "--") {
            postTerminatorArgs = Array(tokens[(terminatorIndex + 1)...])
            tokens = Array(tokens[..<terminatorIndex])
            terminatorSeen = true
        }

        // Phase 1: Parse named arguments (--flags, --options)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]

            if token.starts(with: "--") {
                let name = String(token.dropFirst(2))
                guard let arg = definedArgs.first(where: { $0.valueName == name }) else {
                    // Unknown named argument - could be for subcommand
                    leftover.append(token)
                    i += 1
                    // Only consume next token if it's not another option and not a subcommand
                    if i < tokens.count && !tokens[i].starts(with: "--") && !subcommandNames.contains(tokens[i]) {
                        leftover.append(tokens[i])
                        i += 1
                    }
                    continue
                }

                switch arg.kind {
                case .flag:
                    providedMap[arg.valueName ?? name, default: []].append("true")
                    tokens.remove(at: i)
                case .option:
                    tokens.remove(at: i)
                    let values = try parseOptionValues(arg: arg, tokens: &tokens, currentIndex: &i)
                    providedMap[arg.valueName ?? name, default: []].append(contentsOf: values)
                default:
                    throw TemplateError.unexpectedNamedArgument(name: name)
                }
            } else {
                i += 1
            }
        }

        // Phase 2: Parse positional arguments in order
        var positionalIndex = 0
        var tokenIndex = 0

        while tokenIndex < tokens.count && positionalIndex < positionalArgs.count {
            let token = tokens[tokenIndex]

            // Skip subcommands for now
            if subcommandNames.contains(token) {
                leftover.append(token)
                tokens.remove(at: tokenIndex)
                continue
            }

            let arg = positionalArgs[positionalIndex]
            let argName = arg.valueName ?? "__positional"

            var values: [String] = []

            // Handle different parsing strategies for positional args
            switch arg.parsingStrategy {
            case .allRemainingInput:
                // Collect all remaining tokens
                values = Array(tokens[tokenIndex...])
                tokens.removeSubrange(tokenIndex...)
                tokenIndex = tokens.count
            case .upToNextOption:
                // Collect tokens until we hit an option or subcommand
                while tokenIndex < tokens.count {
                    let currentToken = tokens[tokenIndex]
                    if currentToken.starts(with: "--") || subcommandNames.contains(currentToken) {
                        break
                    }
                    values.append(currentToken)
                    tokens.remove(at: tokenIndex)
                }
            default:
                if arg.isRepeating {
                    // Collect all remaining non-option tokens for repeating argument
                    while tokenIndex < tokens.count {
                        let currentToken = tokens[tokenIndex]
                        if currentToken.starts(with: "--") || subcommandNames.contains(currentToken) {
                            break
                        }
                        values.append(currentToken)
                        tokens.remove(at: tokenIndex)
                    }
                } else {
                    // Take single token for non-repeating argument
                    values.append(token)
                    tokens.remove(at: tokenIndex)
                }
            }

            // Validate values if restrictions exist
            if let allowed = arg.allValues {
                let invalid = values.filter { !allowed.contains($0) }
                if !invalid.isEmpty {
                    throw TemplateError.invalidValue(
                        argument: argName,
                        invalidValues: invalid,
                        allowed: allowed
                    )
                }
            }

            responses.insert(ArgumentResponse(argument: arg, values: values, isExplicitlyUnset: false))
            positionalIndex += 1
        }

        // Add remaining tokens to leftover
        leftover.append(contentsOf: tokens)

        // Phase 3: Handle special parsing strategies
        for arg in definedArgs {
            let argName = arg.valueName ?? "__unknown"
            switch arg.parsingStrategy {
            case .postTerminator:
                if terminatorSeen {
                    responses.insert(ArgumentResponse(
                        argument: arg,
                        values: postTerminatorArgs,
                        isExplicitlyUnset: false
                    ))
                }
            case .allRemainingInput:
                // Only process if not already handled in positional parsing
                if arg.kind != .positional {
                    responses.insert(ArgumentResponse(argument: arg, values: tokens, isExplicitlyUnset: false))
                    tokens.removeAll()
                }
            case .allUnrecognized:
                responses.insert(ArgumentResponse(argument: arg, values: leftover, isExplicitlyUnset: false))
                leftover.removeAll()
            default:
                // Default parsing already handled above
                break
            }
        }

        // Phase 4: Build responses for named arguments
        for arg in definedArgs.filter({ $0.kind != .positional }) {
            let name = arg.valueName ?? "__unknown"
            guard let values = providedMap[name] else {
                continue
            }

            if let allowed = arg.allValues {
                let invalid = values.filter { !allowed.contains($0) }
                if !invalid.isEmpty {
                    throw TemplateError.invalidValue(
                        argument: name,
                        invalidValues: invalid,
                        allowed: allowed
                    )
                }
            }

            responses.insert(ArgumentResponse(argument: arg, values: values, isExplicitlyUnset: false))
        }

        return (responses, leftover)
    }

    /// Helper method to parse option values based on parsing strategy
    private func parseOptionValues(
        arg: ArgumentInfoV0,
        tokens: inout [String],
        currentIndex: inout Int
    ) throws -> [String] {
        var values: [String] = []

        switch arg.parsingStrategy {
        case .default:
            // Expect the next token to be a value and parse it
            guard currentIndex < tokens.count && !tokens[currentIndex].starts(with: "-") else {
                if arg.isOptional && arg.defaultValue != nil {
                    // Use default value for optional arguments
                    return arg.defaultValue.map { [$0] } ?? []
                }
                throw TemplateError.missingValueForOption(name: arg.valueName ?? "")
            }
            values.append(tokens[currentIndex])
            tokens.remove(at: currentIndex)

        case .scanningForValue:
            // Parse the next token as a value if it exists and isn't an option
            if currentIndex < tokens.count && !tokens[currentIndex].starts(with: "--") {
                values.append(tokens[currentIndex])
                tokens.remove(at: currentIndex)
            } else if let defaultValue = arg.defaultValue {
                values.append(defaultValue)
            }

        case .unconditional:
            // Parse the next token as a value, regardless of its type
            guard currentIndex < tokens.count else {
                if let defaultValue = arg.defaultValue {
                    return [defaultValue]
                }
                throw TemplateError.missingValueForOption(name: arg.valueName ?? "")
            }
            values.append(tokens[currentIndex])
            tokens.remove(at: currentIndex)

        case .upToNextOption:
            // Parse multiple values up to the next option
            while currentIndex < tokens.count && !tokens[currentIndex].starts(with: "--") {
                values.append(tokens[currentIndex])
                tokens.remove(at: currentIndex)
            }
            // If no values found and there's a default, use it
            if values.isEmpty && arg.defaultValue != nil {
                values.append(arg.defaultValue!)
            }

        case .allRemainingInput:
            // Collect all remaining tokens
            values = Array(tokens[currentIndex...])
            tokens.removeSubrange(currentIndex...)

        case .postTerminator, .allUnrecognized:
            // These are handled separately in the main parsing logic
            if currentIndex < tokens.count {
                values.append(tokens[currentIndex])
                tokens.remove(at: currentIndex)
            }
        }

        // Validate values against allowed values if specified
        if let allowed = arg.allValues {
            let invalid = values.filter { !allowed.contains($0) }
            if !invalid.isEmpty {
                throw TemplateError.invalidValue(
                    argument: arg.valueName ?? "",
                    invalidValues: invalid,
                    allowed: allowed
                )
            }
        }

        return values
    }

    public func generateCommandPaths(
        rootCommand: CommandInfoV0,
        args: [String],
        branches: [String]
    ) throws -> [CommandPath] {
        var paths: [CommandPath] = []
        var visitedArgs = Set<ArgumentResponse>()
        var inheritedResponses: [ArgumentResponse] = []

        try dfsWithInheritance(
            command: rootCommand,
            path: [],
            visitedArgs: &visitedArgs,
            inheritedResponses: &inheritedResponses,
            paths: &paths,
            predefinedArgs: args,
            branches: branches,
            branchDepth: 0
        )

        for path in paths {
            print(path.displayFormat())
        }
        return paths
    }

    func dfsWithInheritance(
        command: CommandInfoV0,
        path: [CommandComponent],
        visitedArgs: inout Set<TemplateTestPromptingSystem.ArgumentResponse>,
        inheritedResponses: inout [ArgumentResponse],
        paths: inout [CommandPath],
        predefinedArgs: [String],
        branches: [String],
        branchDepth: Int = 0
    ) throws {
        let allArgs = try convertArguments(from: command)
        let subCommands = self.getSubCommand(from: command) ?? []

        let (answeredArgs, leftoverArgs) = try parseAndMatchArguments(
            predefinedArgs,
            definedArgs: allArgs,
            subcommands: subCommands
        )

        // Combine inherited responses with current parsed responses
        let currentArgNames = Set(allArgs.map(\.valueName))
        let relevantInheritedResponses = inheritedResponses.filter { !currentArgNames.contains($0.argument.valueName) }

        var allCurrentResponses = Array(answeredArgs) + relevantInheritedResponses
        visitedArgs.formUnion(answeredArgs)

        // Find missing arguments that need prompting
        let providedArgNames = Set(allCurrentResponses.map(\.argument.valueName))
        let missingArgs = allArgs.filter { arg in
            !providedArgNames.contains(arg.valueName) && arg.valueName != "help" && arg.shouldDisplay
        }

        // Only prompt for missing arguments
        var collected: [String: ArgumentResponse] = [:]
        let newResolvedArgs = try UserPrompter.prompt(for: missingArgs, collected: &collected, hasTTY: self.hasTTY)

        // Add new arguments to current responses and visited set
        allCurrentResponses.append(contentsOf: newResolvedArgs)
        newResolvedArgs.forEach { visitedArgs.insert($0) }

        // Filter to only include arguments defined at this command level
        let currentLevelResponses = allCurrentResponses.filter { currentArgNames.contains($0.argument.valueName) }

        let currentComponent = CommandComponent(
            commandName: command.commandName, arguments: currentLevelResponses
        )

        var newPath = path
        newPath.append(currentComponent)

        // Update inherited responses for next level (pass down all responses for potential inheritance)
        var newInheritedResponses = allCurrentResponses

        // Handle subcommands with auto-detection logic
        if let subcommands = getSubCommand(from: command) {
            // Try to auto-detect a subcommand from leftover args
            if let (index, matchedSubcommand) = leftoverArgs
                .enumerated()
                .compactMap({ i, token -> (Int, CommandInfoV0)? in
                    if let match = subcommands.first(where: { $0.commandName == token }) {
                        print("Detected subcommand '\(match.commandName)' from user input.")
                        return (i, match)
                    }
                    return nil
                })
                .first
            {
                var newLeftoverArgs = leftoverArgs
                newLeftoverArgs.remove(at: index)

                let shouldTraverse: Bool = if branches.isEmpty {
                    true
                } else if branchDepth < (branches.count - 1) {
                    matchedSubcommand.commandName == branches[branchDepth + 1]
                } else {
                    matchedSubcommand.commandName == branches[branchDepth]
                }

                if shouldTraverse {
                    try self.dfsWithInheritance(
                        command: matchedSubcommand,
                        path: newPath,
                        visitedArgs: &visitedArgs,
                        inheritedResponses: &newInheritedResponses,
                        paths: &paths,
                        predefinedArgs: newLeftoverArgs,
                        branches: branches,
                        branchDepth: branchDepth + 1
                    )
                }
            } else {
                // No subcommand detected, process all available subcommands based on branch filter
                for sub in subcommands {
                    let shouldTraverse: Bool = if branches.isEmpty {
                        true
                    } else if branchDepth < (branches.count - 1) {
                        sub.commandName == branches[branchDepth + 1]
                    } else {
                        sub.commandName == branches[branchDepth]
                    }

                    if shouldTraverse {
                        var branchInheritedResponses = newInheritedResponses
                        try dfsWithInheritance(
                            command: sub,
                            path: newPath,
                            visitedArgs: &visitedArgs,
                            inheritedResponses: &branchInheritedResponses,
                            paths: &paths,
                            predefinedArgs: leftoverArgs,
                            branches: branches,
                            branchDepth: branchDepth + 1
                        )
                    }
                }
            }
        } else {
            // No subcommands, this is a leaf command - add to paths
            let fullPathKey = joinCommandNames(newPath)
            let commandPath = CommandPath(
                fullPathKey: fullPathKey, commandChain: newPath
            )
            paths.append(commandPath)
        }

        func joinCommandNames(_ path: [CommandComponent]) -> String {
            path.map(\.commandName).joined(separator: "-")
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
            collected: inout [String: ArgumentResponse],
            hasTTY: Bool = true
        ) throws -> [ArgumentResponse] {
            try arguments
                .filter { $0.valueName != "help" && $0.shouldDisplay }
                .compactMap { arg in
                    let key = arg.preferredName?.name ?? arg.valueName ?? UUID().uuidString

                    if let existing = collected[key] {
                        if hasTTY {
                            print("Using previous value for '\(key)': \(existing.values.joined(separator: ", "))")
                        }
                        return existing
                    }

                    let defaultText = arg.defaultValue.map { " (default: \($0))" } ?? ""
                    let allValuesText = (arg.allValues?.isEmpty == false) ?
                        " [\(arg.allValues!.joined(separator: ", "))]" : ""
                    let completionText = self.generateCompletionHint(for: arg)
                    let promptMessage = "\(arg.abstract ?? "")\(allValuesText)\(completionText)\(defaultText):"

                    var values: [String] = []

                    switch arg.kind {
                    case .flag:
                        if !hasTTY && arg.isOptional == false && arg.defaultValue == nil {
                            fatalError(
                                "Required argument '\(arg.valueName ?? "")' not provided and no interactive terminal available"
                            )
                        }

                        var confirmed: Bool? = nil
                        if hasTTY {
                            confirmed = try promptForConfirmation(
                                prompt: promptMessage,
                                defaultBehavior: arg.defaultValue?.lowercased() == "true",
                                isOptional: arg.isOptional
                            )
                        } else if let defaultValue = arg.defaultValue {
                            confirmed = defaultValue.lowercased() == "true"
                        }

                        if let confirmed {
                            values = [confirmed ? "true" : "false"]
                        } else if arg.isOptional {
                            // Flag was explicitly unset
                            let response = ArgumentResponse(argument: arg, values: [], isExplicitlyUnset: true)
                            collected[key] = response
                            return response
                        } else {
                            throw TemplateError.missingRequiredArgumentWithoutTTY(name: arg.valueName ?? "")
                        }

                    case .option, .positional:
                        if !hasTTY && arg.isOptional == false && arg.defaultValue == nil {
                            fatalError(
                                "Required argument '\(arg.valueName ?? "")' not provided and no interactive terminal available"
                            )
                        }

                        if hasTTY {
                            let nilSuffix = arg.isOptional && arg
                                .defaultValue == nil ? " (or enter \"nil\" to unset)" : ""
                            print(promptMessage + nilSuffix)
                        }

                        if arg.isRepeating {
                            if hasTTY {
                                while let input = readLine(), !input.isEmpty {
                                    if input.lowercased() == "nil" && arg.isOptional {
                                        // Clear the values array to explicitly unset
                                        values = []
                                        let response = ArgumentResponse(
                                            argument: arg,
                                            values: values,
                                            isExplicitlyUnset: true
                                        )
                                        collected[key] = response
                                        return response
                                    }
                                    if let allowed = arg.allValues, !allowed.contains(input) {
                                        print(
                                            "Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))"
                                        )
                                        continue
                                    }
                                    values.append(input)
                                }
                            }
                            if values.isEmpty, let def = arg.defaultValue {
                                values = [def]
                            }
                        } else {
                            let input = hasTTY ? readLine() : nil
                            if let input, !input.isEmpty {
                                if input.lowercased() == "nil" && arg.isOptional {
                                    values = []
                                    let response = ArgumentResponse(
                                        argument: arg,
                                        values: values,
                                        isExplicitlyUnset: true
                                    )
                                    collected[key] = response
                                    return response
                                } else {
                                    if let allowed = arg.allValues, !allowed.contains(input) {
                                        if hasTTY {
                                            print(
                                                "Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))"
                                            )
                                            print(
                                                "Or try completion suggestions: \(self.generateCompletionSuggestions(for: arg, input: input))"
                                            )
                                            fatalError("Invalid value provided")
                                        } else {
                                            throw TemplateError.invalidValue(
                                                argument: arg.valueName ?? "",
                                                invalidValues: [input],
                                                allowed: allowed
                                            )
                                        }
                                    }
                                    values = [input]
                                }
                            } else if let def = arg.defaultValue {
                                values = [def]
                            } else if arg.isOptional == false {
                                if hasTTY {
                                    fatalError("Required argument '\(arg.valueName ?? "")' not provided.")
                                } else {
                                    throw TemplateError.missingRequiredArgumentWithoutTTY(name: arg.valueName ?? "")
                                }
                            }
                        }
                    }

                    let response = ArgumentResponse(argument: arg, values: values, isExplicitlyUnset: false)
                    collected[key] = response
                    return response
                }
        }

        /// Generates completion hint text based on CompletionKindV0
        private static func generateCompletionHint(for arg: ArgumentInfoV0) -> String {
            guard let completionKind = arg.completionKind else { return "" }

            switch completionKind {
            case .list(let values):
                return " (suggestions: \(values.joined(separator: ", ")))"
            case .file(let extensions):
                if extensions.isEmpty {
                    return " (file completion available)"
                } else {
                    return " (file completion: .\(extensions.joined(separator: ", .")))"
                }
            case .directory:
                return " (directory completion available)"
            case .shellCommand(let command):
                return " (shell completions available: \(command))"
            case .custom, .customAsync:
                return " (custom completions available)"
            case .customDeprecated:
                return " (custom completions available)"
            }
        }

        /// Generates completion suggestions based on input and CompletionKindV0
        private static func generateCompletionSuggestions(for arg: ArgumentInfoV0, input: String) -> String {
            guard let completionKind = arg.completionKind else {
                return "No completions available"
            }

            switch completionKind {
            case .list(let values):
                let suggestions = values.filter { $0.hasPrefix(input) }
                return suggestions.isEmpty ? "No matching suggestions" : suggestions.joined(separator: ", ")
            case .file, .directory, .shellCommand, .custom, .customAsync, .customDeprecated:
                return "Use system completion for suggestions"
            }
        }
    }

    /// Prompts the user for a yes/no confirmation.
    ///
    /// - Parameters:
    ///   - prompt: The prompt message to display.
    ///   - defaultBehavior: The default value if the user provides no input.
    ///   - isOptional: Whether the argument is optional and can be explicitly unset.
    /// - Returns: `true` if the user confirmed, `false` if denied, `nil` if explicitly unset.
    /// - Throws: TemplateError if required argument missing without TTY

    private static func promptForConfirmation(
        prompt: String,
        defaultBehavior: Bool?,
        isOptional: Bool
    ) throws -> Bool? {
        var suffix = defaultBehavior == true ? " [Y/n]" : defaultBehavior == false ? " [y/N]" : " [y/n]"

        if isOptional && defaultBehavior == nil {
            suffix = suffix + " or enter \"nil\" to unset."
        }
        print(prompt + suffix, terminator: " ")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            if let defaultBehavior {
                return defaultBehavior
            } else if isOptional {
                return nil
            } else {
                throw TemplateError.missingRequiredArgumentWithoutTTY(name: "confirmation")
            }
        }

        switch input {
        case "y", "yes": return true
        case "n", "no": return false
        case "nil":
            if isOptional {
                return nil
            } else {
                throw TemplateError.missingRequiredArgumentWithoutTTY(name: "confirmation")
            }
        case "":
            if let defaultBehavior {
                return defaultBehavior
            } else if isOptional {
                return nil
            } else {
                throw TemplateError.missingRequiredArgumentWithoutTTY(name: "confirmation")
            }
        default:
            if let defaultBehavior {
                return defaultBehavior
            } else if isOptional {
                return nil
            } else {
                throw TemplateError.missingRequiredArgumentWithoutTTY(name: "confirmation")
            }
        }
    }

    /// Represents a user's response to an argument prompt.

    public struct ArgumentResponse: Hashable {
        /// The argument metadata.
        let argument: ArgumentInfoV0

        /// The values provided by the user.
        public let values: [String]

        /// Whether the argument was explicitly unset (nil) by the user.
        public let isExplicitlyUnset: Bool

        /// Returns the command line fragments representing this argument and its values.
        public var commandLineFragments: [String] {
            // If explicitly unset, don't generate any command line fragments
            guard !self.isExplicitlyUnset else { return [] }

            guard let name = argument.valueName else {
                return self.values
            }

            switch self.argument.kind {
            case .flag:
                return self.values.first == "true" ? ["--\(name)"] : []
            case .option:
                if self.argument.isRepeating {
                    return self.values.flatMap { ["--\(name)", $0] }
                } else {
                    return self.values.flatMap { ["--\(name)", $0] }
                }
            case .positional:
                return self.values
            }
        }

        /// Initialize with explicit unset state
        public init(argument: ArgumentInfoV0, values: [String], isExplicitlyUnset: Bool = false) {
            self.argument = argument
            self.values = values
            self.isExplicitlyUnset = isExplicitlyUnset
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.argument.valueName)
        }

        public static func == (lhs: ArgumentResponse, rhs: ArgumentResponse) -> Bool {
            lhs.argument.valueName == rhs.argument.valueName
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
    case missingRequiredArgumentWithoutTTY(name: String)
    case noTTYForSubcommandSelection
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
        case .missingRequiredArgumentWithoutTTY(name: let name):
            "Required argument '\(name)' not provided and no interactive terminal available"
        case .noTTYForSubcommandSelection:
            "Cannot select subcommand interactively - no terminal available"
        }
    }
}
