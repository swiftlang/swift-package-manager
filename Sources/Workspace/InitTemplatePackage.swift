//
//  InitTemplatePackage.swift
//  SwiftPM
//
//  Created by John Bute on 2025-05-13.
//

import ArgumentParserToolInfo
import Basics
import Foundation
import PackageModel
import PackageModelSyntax
import SPMBuildCore
import SwiftParser
import System
import TSCBasic
import TSCUtility

/// A class responsible for initializing a Swift package from a specified template.
///
/// This class handles creating the package structure, applying a template dependency
/// to the package manifest, and optionally prompting the user for input to customize
/// the generated package.
///
/// It supports different types of templates (local, git, registry) and multiple
/// testing libraries.
///
/// Usage:
/// - Initialize an instance with the package name, template details, file system, destination path, etc.
/// - Call `setupTemplateManifest()` to create the package and add the template dependency.
/// - Use `promptUser(tool:)` to interactively prompt the user for command line argument values.

public final class InitTemplatePackage {
    /// The kind of package dependency to add for the template.
    let packageDependency: MappablePackageDependency.Kind
    /// The set of testing libraries supported by the generated package.
    public var supportedTestingLibraries: Set<TestingLibrary>

    /// The file system abstraction to use for file operations.
    let fileSystem: FileSystem

    /// The absolute path where the package will be created.
    let destinationPath: Basics.AbsolutePath

    /// Configuration information from the installed Swift Package Manager toolchain.
    let installedSwiftPMConfiguration: InstalledSwiftPMConfiguration
    /// The name of the package to create.

    var packageName: String

    /// The path to the template files.
    var templatePath: Basics.AbsolutePath

    /// The type of package to create (e.g., library, executable).
    let packageType: InitPackage.PackageType

    /// Options used to configure package initialization.
    public struct InitPackageOptions {
        /// The type of package to create.
        public var packageType: InitPackage.PackageType

        /// The set of supported testing libraries to include in the package.
        public var supportedTestingLibraries: Set<TestingLibrary>

        /// The list of supported platforms to target in the manifest.
        ///
        /// Note: Currently only Apple platforms are supported.
        public var platforms: [SupportedPlatform]

        /// Creates a new `InitPackageOptions` instance.
        /// - Parameters:
        ///   - packageType: The type of package to create.
        ///   - supportedTestingLibraries: The set of testing libraries to support.
        ///   - platforms: The list of supported platforms (default is empty).

        public init(
            packageType: InitPackage.PackageType,
            supportedTestingLibraries: Set<TestingLibrary>,
            platforms: [SupportedPlatform] = []
        ) {
            self.packageType = packageType
            self.supportedTestingLibraries = supportedTestingLibraries
            self.platforms = platforms
        }
    }

    /// The type of template source.
    public enum TemplateSource: String, CustomStringConvertible {
        case local
        case git
        case registry

        public var description: String {
            rawValue
        }
    }

    /// Creates a new `InitTemplatePackage` instance.
    ///
    /// - Parameters:
    ///   - name: The name of the package to create.
    ///   - templateName: The name of the template to use.
    ///   - initMode: The kind of package dependency to add for the template.
    ///   - templatePath: The file system path to the template files.
    ///   - fileSystem: The file system to use for operations.
    ///   - packageType: The type of package to create (e.g., library, executable).
    ///   - supportedTestingLibraries: The set of testing libraries to support.
    ///   - destinationPath: The directory where the new package should be created.
    ///   - installedSwiftPMConfiguration: Configuration from the SwiftPM toolchain.
    public init(
        name: String,
        initMode: MappablePackageDependency.Kind,
        templatePath: Basics.AbsolutePath,
        fileSystem: FileSystem,
        packageType: InitPackage.PackageType,
        supportedTestingLibraries: Set<TestingLibrary>,
        destinationPath: Basics.AbsolutePath,
        installedSwiftPMConfiguration: InstalledSwiftPMConfiguration,
    ) {
        self.packageName = name
        self.packageDependency = initMode
        self.templatePath = templatePath
        self.packageType = packageType
        self.supportedTestingLibraries = supportedTestingLibraries
        self.destinationPath = destinationPath
        self.installedSwiftPMConfiguration = installedSwiftPMConfiguration
        self.fileSystem = fileSystem
    }

    /// Sets up the package manifest by creating the package structure and
    /// adding the template dependency to the manifest.
    ///
    /// This method initializes an empty package using `InitPackage`, writes the
    /// package structure, and then applies the template dependency to the manifest file.
    ///
    /// - Throws: An error if package initialization or manifest modification fails.
    public func setupTemplateManifest() throws {
        // initialize empty swift package
        let initializedPackage = try InitPackage(
            name: self.packageName,
            options: .init(packageType: self.packageType, supportedTestingLibraries: self.supportedTestingLibraries),
            destinationPath: self.destinationPath,
            installedSwiftPMConfiguration: self.installedSwiftPMConfiguration,
            fileSystem: self.fileSystem
        )
        try initializedPackage.writePackageStructure()
        try self.initializePackageFromTemplate()
    }

    /// Initializes the package by adding the template dependency to the manifest.
    ///
    /// - Throws: An error if adding the dependency or modifying the manifest fails.
    private func initializePackageFromTemplate() throws {
        try self.addTemplateDepenency()
    }

    /// Adds the template dependency to the package manifest.
    ///
    /// This reads the manifest file, parses it into a syntax tree, modifies it
    /// to include the template dependency, and then writes the updated manifest
    /// back to disk.
    ///
    /// - Throws: An error if the manifest file cannot be read, parsed, or modified.

    private func addTemplateDepenency() throws {
        let manifestPath = self.destinationPath.appending(component: Manifest.filename)
        let manifestContents: ByteString

        do {
            manifestContents = try self.fileSystem.readFileContents(manifestPath)
        } catch {
            throw StringError("Cannot find package manifest in \(manifestPath)")
        }

        let manifestSyntax = manifestContents.withData { data in
            data.withUnsafeBytes { buffer in
                buffer.withMemoryRebound(to: UInt8.self) { buffer in
                    Parser.parse(source: buffer)
                }
            }
        }

        let editResult = try AddPackageDependency.addPackageDependency(
            self.packageDependency, to: manifestSyntax
        )

        try editResult.applyEdits(
            to: self.fileSystem,
            manifest: manifestSyntax,
            manifestPath: manifestPath,
            verbose: false
        )
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
    /// - Returns: A list of command line invocations (`[[String]]`), each representing a full CLI command.
    ///            Each entry includes only arguments relevant to the specific command or subcommand level.
    ///
    /// - Throws: An error if argument parsing or user prompting fails.

    public func promptUser(command: CommandInfoV0, arguments: [String], subcommandTrail: [String] = [], inheritedResponses: [ArgumentResponse] = []) throws -> [[String]] {

        var commandLines = [[String]]()

        let allArgs = try convertArguments(from: command)
        let (providedResponses, leftoverArgs) = try self.parseAndMatchArgumentsWithLeftovers(arguments, definedArgs: allArgs)

        let missingArgs = self.findMissingArguments(from: allArgs, excluding: providedResponses)

        var collectedResponses: [String: ArgumentResponse] = [:]
        let promptedResponses = UserPrompter.prompt(for: missingArgs, collected: &collectedResponses)

        // Combine all inherited + current-level responses
        let allCurrentResponses = inheritedResponses + providedResponses + promptedResponses

        let currentArgNames = Set(allArgs.map { $0.valueName })
        let currentCommandResponses = allCurrentResponses.filter { currentArgNames.contains($0.argument.valueName) }

        let currentArgs = self.buildCommandLine(from: currentCommandResponses)
        let fullCommand = subcommandTrail + currentArgs

        commandLines.append(fullCommand)


        if let subCommands = getSubCommand(from: command) {
            // Try to auto-detect a subcommand from leftover args
            if let (index, matchedSubcommand) = leftoverArgs
                .enumerated()
                .compactMap({ (i, token) -> (Int, CommandInfoV0)? in
                    if let match = subCommands.first(where: { $0.commandName == token }) {
                        print("Detected subcommand '\(match.commandName)' from user input.")
                        return (i, match)
                    }
                    return nil
                })
                .first {

                var newTrail = subcommandTrail
                newTrail.append(matchedSubcommand.commandName)

                var newArgs = leftoverArgs
                newArgs.remove(at: index)

                let subCommandLines = try self.promptUser(
                    command: matchedSubcommand,
                    arguments: newArgs,
                    subcommandTrail: newTrail,
                    inheritedResponses: allCurrentResponses
                )

                commandLines.append(contentsOf: subCommandLines)
            } else {
                // Fall back to interactive prompt
                let chosenSubcommand = try self.promptUserForSubcommand(for: subCommands)

                var newTrail = subcommandTrail
                newTrail.append(chosenSubcommand.commandName)

                let subCommandLines = try self.promptUser(
                    command: chosenSubcommand,
                    arguments: leftoverArgs,
                    subcommandTrail: newTrail,
                    inheritedResponses: allCurrentResponses
                )

                commandLines.append(contentsOf: subCommandLines)
            }
        }

        return commandLines
    }

    /// Prompts the user to select a subcommand from a list of available options.
    ///
    /// This method prints a list of available subcommands, including their names and brief descriptions.
    /// It then interactively prompts the user to enter the name of a subcommand. If the entered name
    /// matches one of the available subcommands, that subcommand is returned. Otherwise, the user is
    /// repeatedly prompted until a valid subcommand name is provided.
    ///
    /// - Parameter commands: An array of `CommandInfoV0` representing the available subcommands.
    ///
    /// - Returns: The `CommandInfoV0` instance corresponding to the subcommand selected by the user.
    ///
    /// - Throws: This method does not throw directly, but may propagate errors thrown by downstream callers.

    private func promptUserForSubcommand(for commands: [CommandInfoV0]) throws -> CommandInfoV0 {

        print("Choose from the following:\n")

        for command in commands {
            print("""
              Name: \(command.commandName)
              About: \(command.abstract ?? "")
            """)
        }

        print("Type the name of the option:")
        while true {
            if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty {
                if let match = commands.first(where: { $0.commandName == input }) {
                    return match
                } else {
                    print("No option found with name '\(input)'. Please try again:")
                }
            } else {
                print("Please enter a valid option name:")
            }
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
    private func getSubCommand(from command: CommandInfoV0) -> [CommandInfoV0]? {
        guard let subcommands = command.subcommands else { return nil }

        let filteredSubcommands = subcommands.filter { $0.commandName.lowercased() != "help" }

        guard !filteredSubcommands.isEmpty else { return nil }

        return filteredSubcommands
    }
    /// Parses predetermined arguments and validates the arguments
    ///
    /// This method converts user's predetermined arguments into the ArgumentResponse struct
    /// and validates the user's predetermined arguments against the template's available arguments.
    ///
    ///  - Parameter input: The input arguments from the consumer.
    ///  - parameter definedArgs: the arguments defined by the template
    ///  - Returns: An array of responses to the tool's arguments
    ///  - Throws: Invalid values if the value is not within all the possible values allowed by the argument
    ///  - Throws: Throws an unexpected argument if the user specifies an argument that does not match any arguments
    ///     defined by the template.
    private func parseAndMatchArgumentsWithLeftovers(
        _ input: [String],
        definedArgs: [ArgumentInfoV0]
    ) throws -> ([ArgumentResponse], [String]) {
        var responses: [ArgumentResponse] = []
        var providedMap: [String: [String]] = [:]
        var leftover: [String] = []
        var index = 0

        while index < input.count {
            let token = input[index]

            if token.starts(with: "--") {
                let name = String(token.dropFirst(2))
                guard let arg = definedArgs.first(where: { $0.valueName == name }) else {
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
                // Positional, include it anyway
                leftover.append(token)
            }

            index += 1
        }

        for arg in definedArgs {
            let name = arg.valueName ?? "__positional"
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

            responses.append(ArgumentResponse(argument: arg, values: values))
            providedMap[name] = nil
        }

        return (responses, leftover)
    }

    /// Determines the rest of the arguments that need a user's response
    ///
    /// This method determines the rest of the responses needed from the user to complete the generation of a template
    ///
    ///
    ///  - Parameter all: All the arguments from the template.
    ///  - parameter excluding: The arguments that do not need prompting
    ///  - Returns: An array of arguments that need to be prompted for user response

    private func findMissingArguments(
        from all: [ArgumentInfoV0],
        excluding responses: [ArgumentResponse]
    ) -> [ArgumentInfoV0] {
        let seen = Set(responses.map { $0.argument.valueName ?? "__positional" })

        return all.filter { arg in
            let name = arg.valueName ?? "__positional"
            return !seen.contains(name)
        }
    }

    /// Converts the command information into an array of argument metadata.
    ///
    /// - Parameter command: The command info object.
    /// - Returns: An array of argument info objects.
    /// - Throws: `TemplateError.noArguments` if the command has no arguments.

    private func convertArguments(from command: CommandInfoV0) throws -> [ArgumentInfoV0] {
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

    /// Builds an array of command line argument strings from the given argument responses.
    ///
    /// - Parameter responses: The array of argument responses containing user inputs.
    /// - Returns: An array of strings representing the command line arguments.

    func buildCommandLine(from responses: [ArgumentResponse]) -> [String] {
        responses.flatMap(\.commandLineFragments)
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

    public struct ArgumentResponse {
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
