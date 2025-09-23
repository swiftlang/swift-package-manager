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
/// - Coordinating template plugin execution through ``TemplatePluginCoordinator``
/// - Generating command paths based on user arguments and branch filters
/// - Managing the interaction between template plugins and the testing infrastructure
///
/// ## Usage
///
/// ```swift
/// let manager = try await TemplateTesterPluginManager(
///     swiftCommandState: commandState,
///     template: "MyTemplate",
///     scratchDirectory: scratchPath,
///     args: ["--name", "TestProject"],
///     branches: ["create", "swift"],
///     buildSystem: .native
/// )
///
/// let commandPaths = try await manager.run()
/// let plugin = try manager.loadTemplatePlugin()
/// ```
///
/// - Note: This manager is designed specifically for testing workflows and should not be used
///   in production template initialization scenarios.
public struct TemplateTesterPluginManager: TemplatePluginManager {
    /// The Swift command state containing build configuration and observability scope.
    private let swiftCommandState: SwiftCommandState
    
    /// The name of the template to test. If nil, will be auto-detected from the package manifest.
    private let template: String?
    
    /// The scratch directory path where temporary testing files are created.
    private let scratchDirectory: Basics.AbsolutePath
    
    /// The command line arguments to pass to the template plugin during testing.
    private let args: [String]
    
    /// The loaded package graph containing all resolved packages and dependencies.
    private let packageGraph: ModulesGraph
    
    /// The branch names used to filter which command paths to generate during testing.
    private let branches: [String]
    
    /// The coordinator responsible for managing template plugin operations.
    private let coordinator: TemplatePluginCoordinator
    
    /// The build system provider kind to use for building template dependencies.
    private let buildSystem: BuildSystemProvider.Kind

    /// The root package from the loaded package graph.
    ///
    /// - Returns: The first root package in the package graph.
    /// - Precondition: The package graph must contain at least one root package.
    /// - Warning: This property will cause a fatal error if no root package is found.
    private var rootPackage: ResolvedPackage {
        guard let root = packageGraph.rootPackages.first else {
            fatalError("No root package found in the package graph. Ensure the template package is properly configured.")
        }
        return root
    }

    /// Initializes a new template tester plugin manager.
    ///
    /// This initializer performs the complete setup required for template testing, including
    /// loading the package graph and setting up the plugin coordinator.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The Swift command state containing build configuration and observability.
    ///   - template: The name of the template to test. If not provided, will be auto-detected.
    ///   - scratchDirectory: The directory path for temporary testing files.
    ///   - args: The command line arguments to pass to the template plugin.
    ///   - branches: The branch names to filter command path generation.
    ///   - buildSystem: The build system provider to use for compilation.
    ///
    /// - Throws: 
    ///   - `PackageGraphError` if the package graph cannot be loaded
    ///   - `FileSystemError` if the scratch directory is invalid
    ///   - `TemplatePluginError` if the plugin coordinator setup fails
    init(
        swiftCommandState: SwiftCommandState,
        template: String,
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

    /// Executes the template testing workflow and generates command paths.
    ///
    /// This method performs the complete testing workflow:
    /// 1. Loads the template plugin from the package graph
    /// 2. Dumps tool information to understand available commands and arguments
    /// 3. Prompts the user for template arguments based on the tool info
    /// 4. Generates command paths for testing different argument combinations
    ///
    /// - Returns: An array of ``CommandPath`` objects representing different command execution paths.
    /// - Throws:
    ///   - `TemplatePluginError` if the plugin cannot be loaded
    ///   - `ToolInfoError` if tool information cannot be extracted
    ///   - `TemplateError` if argument prompting fails
    ///
    /// ## Example
    /// ```swift
    /// let paths = try await manager.run()
    /// for path in paths {
    ///     print(path.displayFormat())
    /// }
    /// ```
    func run() async throws -> [CommandPath] {
        let plugin = try coordinator.loadTemplatePlugin(from: self.packageGraph)
        let toolInfo = try await coordinator.dumpToolInfo(
            using: plugin,
            from: self.packageGraph,
            rootPackage: self.rootPackage
        )

        return try self.promptUserForTemplateArguments(using: toolInfo)
    }

    /// Prompts the user for template arguments and generates command paths.
    ///
    /// Creates a ``TemplateTestPromptingSystem`` instance and uses it to generate
    /// command paths based on the provided tool information and user arguments.
    ///
    /// - Parameter toolInfo: The tool information extracted from the template plugin.
    /// - Returns: An array of ``CommandPath`` representing different argument combinations.
    /// - Throws: `TemplateError` if argument parsing or command path generation fails.
    private func promptUserForTemplateArguments(using toolInfo: ToolInfoV0) throws -> [CommandPath] {
        try TemplateTestPromptingSystem(hasTTY: self.swiftCommandState.outputStream.isTTY).generateCommandPaths(
            rootCommand: toolInfo.command,
            args: self.args,
            branches: self.branches
        )
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

/// Represents a complete command execution path for template testing.
///
/// A `CommandPath` encapsulates a sequence of commands and their arguments that form
/// a complete execution path through a template's command structure. This is used during
/// template testing to represent different ways the template can be invoked.
///
/// ## Properties
///
/// - ``fullPathKey``: A string identifier for the command path, typically formed by joining command names
/// - ``commandChain``: An ordered sequence of ``CommandComponent`` representing the command hierarchy
///
/// ## Usage
///
/// ```swift
/// let path = CommandPath(
///     fullPathKey: "init-swift-executable",
///     commandChain: [rootCommand, initCommand, swiftCommand, executableCommand]
/// )
/// print(path.displayFormat())
/// ```
public struct CommandPath {
    /// The unique identifier for this command path, typically formed by joining command names with hyphens.
    public let fullPathKey: String
    
    /// The ordered sequence of command components that make up this execution path.
    public let commandChain: [CommandComponent]
}

/// Represents a single command component within a command execution path.
///
/// A `CommandComponent` contains a command name and its associated arguments.
/// Multiple components are chained together to form a complete ``CommandPath``.
///
/// ## Properties
///
/// - ``commandName``: The name of the command (e.g., "init", "swift", "executable")
/// - ``arguments``: The arguments and their values for this specific command level
///
/// ## Example
///
/// ```swift
/// let component = CommandComponent(
///     commandName: "init",
///     arguments: [nameArgument, typeArgument]
/// )
/// ```
public struct CommandComponent {
    /// The name of this command component.
    let commandName: String
    
    /// The arguments associated with this command component.
    let arguments: [TemplateTestPromptingSystem.ArgumentResponse]
}

extension CommandPath {
    /// Formats the command path for display purposes.
    ///
    /// Creates a human-readable representation of the command path, including:
    /// - The complete command path hierarchy
    /// - The flat execution format suitable for command-line usage
    ///
    /// - Returns: A formatted string representation of the command path.
    ///
    /// ## Example Output
    /// ```
    /// Command Path: init swift executable
    /// Execution Format:
    ///
    /// init --name MyProject swift executable --target-name MyTarget
    /// ```
    func displayFormat() -> String {
        let commandNames = self.commandChain.map(\.commandName)
        let fullPath = commandNames.joined(separator: " ")

        var result = "Command Path: \(fullPath) \nExecution Format: \n\n"

        // Build flat command format: [Command command-args sub-command sub-command-args ...]
        let flatCommand = self.buildFlatCommandDisplay()
        result += "\(flatCommand)\n\n"

        return result
    }

    /// Builds a flat command representation suitable for command-line execution.
    ///
    /// Flattens the command chain into a single array of strings that can be executed
    /// as a command-line invocation. Skips the root command name and includes all
    /// subcommands and their arguments in the correct order.
    ///
    /// - Returns: A space-separated string representing the complete command line.
    ///
    /// ## Format
    /// The returned format follows the pattern:
    /// `[subcommand1] [args1] [subcommand2] [args2] ...`
    ///
    /// The root command name is omitted as it's typically the executable name.
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

    /// Formats argument responses for command-line display.
    ///
    /// Takes an array of argument responses and formats them as command-line arguments
    /// with proper flag and option syntax.
    ///
    /// - Parameter argumentResponses: The argument responses to format.
    /// - Returns: A formatted string with each argument on a separate line, suitable for multi-line display.
    ///
    /// ## Example Output
    /// ```
    ///   --name ProjectName \
    ///   --type executable \
    ///   --target-name MainTarget
    /// ```
    ///
    /// - Note: This method is currently unused but preserved for potential future display formatting needs.
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

/// A system for prompting users and generating command paths during template testing.
///
/// `TemplateTestPromptingSystem` handles the complex logic of parsing user input,
/// prompting for missing arguments, and generating all possible command execution paths
/// based on template tool information.
///
/// ## Key Features
///
/// - **Argument Parsing**: Supports flags, options, and positional arguments with various parsing strategies
/// - **Interactive Prompting**: Prompts users for missing required arguments when a TTY is available
/// - **Command Path Generation**: Uses depth-first search to generate all valid command combinations
/// - **Branch Filtering**: Supports filtering command paths based on specified branch names
/// - **Validation**: Validates argument values against allowed value sets and completion kinds
///
/// ## Usage
///
/// ```swift
/// let promptingSystem = TemplateTestPromptingSystem(hasTTY: true)
/// let commandPaths = try promptingSystem.generateCommandPaths(
///     rootCommand: toolInfo.command,
///     args: userArgs,
///     branches: ["init", "swift"]
/// )
/// ```
///
/// ## Argument Parsing Strategies
///
/// The system supports various parsing strategies defined in `ArgumentParserToolInfo`:
/// - `.default`: Standard argument parsing
/// - `.scanningForValue`: Scans for values while allowing defaults
/// - `.unconditional`: Always consumes the next token as a value
/// - `.upToNextOption`: Consumes tokens until the next option is encountered
/// - `.allRemainingInput`: Consumes all remaining input tokens
/// - `.postTerminator`: Handles arguments after a `--` terminator
/// - `.allUnrecognized`: Captures unrecognized arguments
public class TemplateTestPromptingSystem {
    /// Indicates whether a TTY (terminal) is available for interactive prompting.
    ///
    /// When `true`, the system can prompt users interactively for missing arguments.
    /// When `false`, the system relies on default values and may throw errors for required arguments.
    private let hasTTY: Bool

    /// Initializes a new template test prompting system.
    ///
    /// - Parameter hasTTY: Whether interactive terminal prompting is available. Defaults to `true`.
    public init(hasTTY: Bool = true) {
        self.hasTTY = hasTTY
    }

    /// Parses and matches provided arguments against defined argument specifications.
    ///
    /// This method performs comprehensive argument parsing, handling:
    /// - Named arguments (flags and options starting with `--`)
    /// - Positional arguments in their defined order
    /// - Special parsing strategies like post-terminator and all-remaining-input
    /// - Argument validation against allowed value sets
    ///
    /// - Parameters:
    ///   - input: The input arguments to parse
    ///   - definedArgs: The argument definitions from the template tool info
    ///   - subcommands: Available subcommands for context during parsing
    ///
    /// - Returns: A tuple containing:
    ///   - `Set<ArgumentResponse>`: Successfully parsed and matched arguments
    ///   - `[String]`: Leftover arguments that couldn't be matched (potentially for subcommands)
    ///
    /// - Throws:
    ///   - `TemplateError.unexpectedNamedArgument` for unknown named arguments
    ///   - `TemplateError.invalidValue` for arguments with invalid values
    ///   - `TemplateError.missingValueForOption` for options missing required values
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

    /// Parses option values based on the argument's parsing strategy.
    ///
    /// This helper method handles the complexity of parsing option values according to
    /// different parsing strategies defined in the argument specification.
    ///
    /// - Parameters:
    ///   - arg: The argument definition containing parsing strategy and validation rules
    ///   - tokens: The remaining input tokens (modified in-place as tokens are consumed)
    ///   - currentIndex: The current position in the tokens array (modified in-place)
    ///
    /// - Returns: An array of parsed values for the option
    ///
    /// - Throws:
    ///   - `TemplateError.missingValueForOption` when required values are missing
    ///   - `TemplateError.invalidValue` when values don't match allowed value constraints
    ///
    /// ## Supported Parsing Strategies
    ///
    /// - **Default**: Expects the next token to be a value
    /// - **Scanning for Value**: Scans for a value, allowing defaults if none found
    /// - **Unconditional**: Always consumes the next token regardless of its format
    /// - **Up to Next Option**: Consumes tokens until another option is encountered
    /// - **All Remaining Input**: Consumes all remaining tokens
    /// - **Post Terminator/All Unrecognized**: Handled separately in main parsing logic
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

    /// Generates all possible command paths for template testing.
    ///
    /// This is the main entry point for command path generation. It uses a depth-first search
    /// algorithm to explore all possible command combinations, respecting branch filters and
    /// argument inheritance between command levels.
    ///
    /// - Parameters:
    ///   - rootCommand: The root command information from the template tool info
    ///   - args: Predefined arguments provided by the user
    ///   - branches: Branch names to filter which command paths are generated
    ///
    /// - Returns: An array of ``CommandPath`` representing all valid command execution paths
    ///
    /// - Throws: `TemplateError` if argument parsing, validation, or prompting fails
    ///
    /// ## Branch Filtering
    ///
    /// When branches are specified, only command paths that match the branch hierarchy will be generated.
    /// For example, if branches are `["init", "swift"]`, only paths like `init swift executable`
    /// or `init swift library` will be included.
    ///
    /// ## Output
    ///
    /// This method also prints the display format of each generated command path for debugging purposes.
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

    /// Performs depth-first search with argument inheritance to generate command paths.
    ///
    /// This recursive method explores the command tree, handling argument inheritance between
    /// parent and child commands, and generating complete command paths for testing.
    ///
    /// - Parameters:
    ///   - command: The current command being processed
    ///   - path: The current command path being built
    ///   - visitedArgs: Arguments that have been processed (modified in-place)
    ///   - inheritedResponses: Arguments inherited from parent commands (modified in-place)
    ///   - paths: The collection of completed command paths (modified in-place)
    ///   - predefinedArgs: User-provided arguments to parse and apply
    ///   - branches: Branch filter to limit which subcommands are explored
    ///   - branchDepth: Current depth in the branch hierarchy for filtering
    ///
    /// - Throws: `TemplateError` if argument processing fails at any level
    ///
    /// ## Algorithm
    ///
    /// 1. **Parse Arguments**: Parse predefined arguments against current command's argument definitions
    /// 2. **Inherit Arguments**: Combine parsed arguments with inherited arguments from parent commands
    /// 3. **Prompt for Missing**: Prompt user for any missing required arguments
    /// 4. **Create Component**: Build a command component with resolved arguments
    /// 5. **Process Subcommands**: Recursively process subcommands or add leaf paths to results
    ///
    /// ## Argument Inheritance
    ///
    /// Arguments defined at parent command levels are inherited by child commands unless
    /// overridden. This allows for flexible command structures where common arguments
    /// can be specified at higher levels.
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

    /// Retrieves the list of subcommands for a given command, excluding utility commands.
    ///
    /// This method filters out common utility commands like "help" that are typically
    /// auto-generated and not relevant for template testing scenarios.
    ///
    /// - Parameter command: The command to extract subcommands from
    ///
    /// - Returns: An array of valid subcommands, or `nil` if no subcommands exist
    ///
    /// ## Filtering Rules
    ///
    /// - Excludes commands named "help" (case-insensitive)
    /// - Returns `nil` if no subcommands remain after filtering
    /// - Preserves the original order of subcommands
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if let subcommands = getSubCommand(from: command) {
    ///     for subcommand in subcommands {
    ///         // Process each subcommand
    ///     }
    /// }
    /// ```
    func getSubCommand(from command: CommandInfoV0) -> [CommandInfoV0]? {
        guard let subcommands = command.subcommands else { return nil }

        let filteredSubcommands = subcommands.filter { $0.commandName.lowercased() != "help" }

        guard !filteredSubcommands.isEmpty else { return nil }

        return filteredSubcommands
    }

    /// Converts command information into an array of argument metadata.
    ///
    /// Extracts and returns the argument definitions from a command, which are used
    /// for parsing user input and generating prompts.
    ///
    /// - Parameter command: The command information object containing argument definitions
    ///
    /// - Returns: An array of ``ArgumentInfoV0`` objects representing the command's arguments
    ///
    /// - Throws: ``TemplateError.noArguments`` if the command has no argument definitions
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let arguments = try convertArguments(from: command)
    /// for arg in arguments {
    ///     print("Argument: \(arg.valueName ?? "unknown")")
    /// }
    /// ```
    func convertArguments(from command: CommandInfoV0) throws -> [ArgumentInfoV0] {
        guard let rawArgs = command.arguments else {
            throw TemplateError.noArguments
        }
        return rawArgs
    }

    /// A utility for prompting users for command argument values.
    ///
    /// `UserPrompter` provides static methods for interactively prompting users to provide
    /// values for command arguments when they haven't been specified via command-line arguments.
    /// It handles different argument types (flags, options, positional) and supports both
    /// interactive (TTY) and non-interactive modes.
    ///
    /// ## Features
    ///
    /// - **Interactive Prompting**: Prompts users when a TTY is available
    /// - **Default Value Handling**: Uses default values when provided and no user input given
    /// - **Value Validation**: Validates input against allowed value constraints
    /// - **Completion Hints**: Provides completion suggestions based on argument metadata
    /// - **Explicit Unset Support**: Allows users to explicitly unset optional arguments with "nil"
    /// - **Repeating Arguments**: Supports prompting for multiple values for repeating arguments
    ///
    /// ## Argument Types
    ///
    /// - **Flags**: Boolean arguments prompted with yes/no confirmation
    /// - **Options**: String arguments with optional value validation
    /// - **Positional**: Arguments that don't use flag syntax
    public enum UserPrompter {
        /// Prompts users for values for missing command arguments.
        ///
        /// This method handles the interactive prompting workflow for arguments that weren't
        /// provided via command-line input. It supports different argument types and provides
        /// appropriate prompts based on the argument's metadata.
        ///
        /// - Parameters:
        ///   - arguments: The argument definitions to prompt for
        ///   - collected: A dictionary to track previously collected argument responses (modified in-place)
        ///   - hasTTY: Whether interactive terminal prompting is available
        ///
        /// - Returns: An array of ``ArgumentResponse`` objects containing user input
        ///
        /// - Throws:
        ///   - ``TemplateError.missingRequiredArgumentWithoutTTY`` for required arguments when no TTY is available
        ///   - ``TemplateError.invalidValue`` for values that don't match validation constraints
        ///
        /// ## Prompting Behavior
        ///
        /// ### With TTY (Interactive Mode)
        /// - Displays descriptive prompts with available options and defaults
        /// - Supports completion hints and value validation
        /// - Allows "nil" input to explicitly unset optional arguments
        /// - Handles repeating arguments by accepting multiple lines of input
        ///
        /// ### Without TTY (Non-Interactive Mode)
        /// - Uses default values when available
        /// - Throws errors for required arguments without defaults
        /// - Validates any provided values against constraints
        ///
        /// ## Example Usage
        ///
        /// ```swift
        /// var collected: [String: ArgumentResponse] = [:]
        /// let responses = try UserPrompter.prompt(
        ///     for: missingArguments,
        ///     collected: &collected,
        ///     hasTTY: true
        /// )
        /// ```
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

        /// Generates completion hint text based on the argument's completion kind.
        ///
        /// Creates user-friendly text describing available completion options for an argument.
        /// This helps users understand what values are expected or available.
        ///
        /// - Parameter arg: The argument definition containing completion information
        ///
        /// - Returns: A formatted hint string, or empty string if no completion info is available
        ///
        /// ## Completion Types
        ///
        /// - **List**: Shows available predefined values
        /// - **File**: Indicates file completion with optional extension filters
        /// - **Directory**: Indicates directory path completion
        /// - **Shell Command**: Shows the shell command used for completion
        /// - **Custom**: Indicates custom completion is available
        ///
        /// ## Example Output
        ///
        /// ```
        /// " (suggestions: swift, objc, cpp)"
        /// " (file completion: .swift, .h)"
        /// " (directory completion available)"
        /// ```
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

        /// Generates completion suggestions based on user input and argument metadata.
        ///
        /// Provides intelligent completion suggestions by filtering available options
        /// based on the user's partial input.
        ///
        /// - Parameters:
        ///   - arg: The argument definition containing completion information
        ///   - input: The user's partial input to match against
        ///
        /// - Returns: A formatted string with matching suggestions, or a message indicating no matches
        ///
        /// ## Behavior
        ///
        /// - **List Completion**: Filters list values that start with the input
        /// - **Other Types**: Defers to system completion mechanisms
        /// - **No Matches**: Returns "No matching suggestions"
        ///
        /// ## Example
        ///
        /// For input "sw" with available values ["swift", "swiftui", "objc"]:
        /// Returns: "swift, swiftui"
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

    /// Prompts the user for a yes/no confirmation with support for default values and explicit unset.
    ///
    /// This method handles boolean flag prompting with sophisticated default value handling
    /// and support for explicitly unsetting optional flags.
    ///
    /// - Parameters:
    ///   - prompt: The message to display to the user
    ///   - defaultBehavior: The default value to use if no input is provided
    ///   - isOptional: Whether the flag can be explicitly unset with "nil"
    ///
    /// - Returns:
    ///   - `true` if the user confirmed (y/yes)
    ///   - `false` if the user denied (n/no)
    ///   - `nil` if the flag was explicitly unset (only for optional flags)
    ///
    /// - Throws: ``TemplateError.missingRequiredArgumentWithoutTTY`` for required flags without defaults
    ///
    /// ## Input Handling
    ///
    /// - **"y", "yes"**: Returns `true`
    /// - **"n", "no"**: Returns `false`
    /// - **"nil"**: Returns `nil` (only for optional flags)
    /// - **Empty input**: Uses default behavior or `nil` for optional flags
    /// - **Invalid input**: Uses default behavior or `nil` for optional flags
    ///
    /// ## Prompt Format
    ///
    /// - With default true: "Prompt message [Y/n]"
    /// - With default false: "Prompt message [y/N]"
    /// - No default: "Prompt message [y/n]"
    /// - Optional: Appends " or enter 'nil' to unset."
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

    /// Represents a user's response to an argument prompt during template testing.
    ///
    /// `ArgumentResponse` encapsulates the user's input for a specific argument,
    /// including the argument metadata, provided values, and whether the argument
    /// was explicitly unset.
    ///
    /// ## Properties
    ///
    /// - ``argument``: The original argument definition from the template tool info
    /// - ``values``: The string values provided by the user
    /// - ``isExplicitlyUnset``: Whether the user explicitly chose to unset this optional argument
    ///
    /// ## Command Line Generation
    ///
    /// The ``commandLineFragments`` property converts the response into command-line arguments:
    /// - **Flags**: Generate `--flag-name` if true, nothing if false
    /// - **Options**: Generate `--option-name value` pairs
    /// - **Positional**: Generate just the values without flag syntax
    /// - **Explicitly Unset**: Generate no fragments
    ///
    /// ## Example
    ///
    /// ```swift
    /// let response = ArgumentResponse(
    ///     argument: nameArgument,
    ///     values: ["MyProject"],
    ///     isExplicitlyUnset: false
    /// )
    /// // commandLineFragments: ["--name", "MyProject"]
    /// ```
    public struct ArgumentResponse: Hashable {
        /// The argument metadata from the template tool information.
        let argument: ArgumentInfoV0

        /// The string values provided by the user for this argument.
        ///
        /// - For flags: Contains "true" or "false"
        /// - For options: Contains the option value(s)
        /// - For positional arguments: Contains the positional value(s)
        /// - For repeating arguments: May contain multiple values
        public let values: [String]

        /// Indicates whether the user explicitly chose to unset this optional argument.
        ///
        /// When `true`, this argument will not generate any command-line fragments,
        /// effectively removing it from the final command invocation.
        public let isExplicitlyUnset: Bool

        /// Converts the argument response into command-line fragments.
        ///
        /// Generates the appropriate command-line representation based on the argument type:
        ///
        /// - **Flags**: 
        ///   - Returns `["--flag-name"]` if the value is "true"
        ///   - Returns `[]` if the value is "false" or explicitly unset
        ///
        /// - **Options**:
        ///   - Returns `["--option-name", "value"]` for single values
        ///   - Returns `["--option-name", "value1", "--option-name", "value2"]` for repeating options
        ///
        /// - **Positional Arguments**:
        ///   - Returns the values directly without any flag syntax
        ///
        /// - **Explicitly Unset**:
        ///   - Returns `[]` regardless of argument type
        ///
        /// - Returns: An array of strings representing command-line arguments
        ///
        /// ## Example Output
        ///
        /// ```swift
        /// // Flag argument (true)
        /// ["--verbose"]
        ///
        /// // Option argument
        /// ["--name", "MyProject"]
        ///
        /// // Repeating option
        /// ["--target", "App", "--target", "Tests"]
        ///
        /// // Positional argument
        /// ["executable"]
        /// ```
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

        /// Initializes a new argument response.
        ///
        /// - Parameters:
        ///   - argument: The argument definition this response corresponds to
        ///   - values: The values provided by the user
        ///   - isExplicitlyUnset: Whether the argument was explicitly unset (defaults to `false`)
        public init(argument: ArgumentInfoV0, values: [String], isExplicitlyUnset: Bool = false) {
            self.argument = argument
            self.values = values
            self.isExplicitlyUnset = isExplicitlyUnset
        }

        /// Computes the hash value for the argument response.
        ///
        /// Hash computation is based solely on the argument's value name to ensure
        /// that responses for the same argument are considered equivalent.
        ///
        /// - Parameter hasher: The hasher to use for combining hash values
        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.argument.valueName)
        }

        /// Determines equality between two argument responses.
        ///
        /// Two responses are considered equal if they correspond to the same argument,
        /// as determined by comparing their value names.
        ///
        /// - Parameters:
        ///   - lhs: The left-hand side argument response
        ///   - rhs: The right-hand side argument response
        ///
        /// - Returns: `true` if both responses are for the same argument, `false` otherwise
        public static func == (lhs: ArgumentResponse, rhs: ArgumentResponse) -> Bool {
            lhs.argument.valueName == rhs.argument.valueName
        }
    }
}

/// Errors that can occur during template testing and argument processing.
///
/// `TemplateError` provides comprehensive error handling for various failure scenarios
/// that can occur during template testing, argument parsing, and user interaction.
///
/// ## Error Categories
///
/// ### File System Errors
/// - ``invalidPath``: Invalid or non-existent file paths
/// - ``manifestAlreadyExists``: Conflicts with existing manifest files
///
/// ### Argument Processing Errors
/// - ``noArguments``: Template has no argument definitions
/// - ``invalidArgument(name:)``: Invalid argument names or definitions
/// - ``unexpectedArgument(name:)``: Unexpected arguments in input
/// - ``unexpectedNamedArgument(name:)``: Unexpected named arguments
/// - ``missingValueForOption(name:)``: Required option values missing
/// - ``invalidValue(argument:invalidValues:allowed:)``: Values that don't match constraints
///
/// ### Command Structure Errors
/// - ``unexpectedSubcommand(name:)``: Invalid subcommand usage
///
/// ### Interactive Mode Errors
/// - ``missingRequiredArgumentWithoutTTY(name:)``: Required arguments in non-interactive mode
/// - ``noTTYForSubcommandSelection``: Subcommand selection requires interactive mode
///
/// ## Usage
///
/// ```swift
/// do {
///     let responses = try parseArguments(input)
/// } catch TemplateError.invalidValue(let arg, let invalid, let allowed) {
///     print("Invalid value for \(arg): \(invalid). Allowed: \(allowed)")
/// }
/// ```
private enum TemplateError: Swift.Error {
    /// The provided file path is invalid or does not exist.
    case invalidPath

    /// A Package.swift manifest file already exists in the target directory.
    case manifestAlreadyExists

    /// The template has no argument definitions to process.
    case noArguments
    
    /// An argument name is invalid or malformed.
    /// - Parameter name: The invalid argument name
    case invalidArgument(name: String)
    
    /// An unexpected argument was encountered during parsing.
    /// - Parameter name: The unexpected argument name
    case unexpectedArgument(name: String)
    
    /// An unexpected named argument (starting with --) was encountered.
    /// - Parameter name: The unexpected named argument
    case unexpectedNamedArgument(name: String)
    
    /// A required value for an option argument is missing.
    /// - Parameter name: The option name missing its value
    case missingValueForOption(name: String)
    
    /// One or more values don't match the argument's allowed value constraints.
    /// - Parameters:
    ///   - argument: The argument name with invalid values
    ///   - invalidValues: The invalid values that were provided
    ///   - allowed: The list of allowed values for this argument
    case invalidValue(argument: String, invalidValues: [String], allowed: [String])
    
    /// An unexpected subcommand was provided in the arguments.
    /// - Parameter name: The unexpected subcommand name
    case unexpectedSubcommand(name: String)
    
    /// A required argument is missing and no interactive terminal is available for prompting.
    /// - Parameter name: The name of the missing required argument
    case missingRequiredArgumentWithoutTTY(name: String)
    
    /// Subcommand selection requires an interactive terminal but none is available.
    case noTTYForSubcommandSelection
}

extension TemplateError: CustomStringConvertible {
    /// A human-readable description of the template error.
    ///
    /// Provides clear, actionable error messages that help users understand
    /// what went wrong and how to fix the issue.
    ///
    /// ## Error Message Format
    ///
    /// Each error type provides a descriptive message:
    /// - **File system errors**: Explain path or file conflicts
    /// - **Argument errors**: Detail specific validation failures with context
    /// - **Interactive errors**: Explain TTY requirements and alternatives
    ///
    /// ## Example Messages
    ///
    /// ```
    /// "Invalid value for --type. Valid values are: executable, library. Also, xyz is not valid."
    /// "Required argument 'name' not provided and no interactive terminal available"
    /// "Invalid subcommand 'build' provided in arguments, arguments only accepts flags, options, or positional arguments. Subcommands are treated via the --branch option"
    /// ```
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
