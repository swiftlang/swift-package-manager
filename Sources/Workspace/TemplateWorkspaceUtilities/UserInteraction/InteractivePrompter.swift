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
import Foundation

public class TemplatePrompter {
    private let hasTTY: Bool

    public init(hasTTY: Bool) {
        self.hasTTY = hasTTY
    }

    public func promptForMissingArguments(
        _ arguments: [ArgumentInfoV0],
        parsed:
        Set<String>
    ) throws -> [ArgumentResponse] {
        var responses: [ArgumentResponse] = []

        for arg in arguments.filter({ $0.valueName != "help" && $0.shouldDisplay
        }) {
            let argName = try getArgumentName(arg)

            // Skip if already parsed
            if parsed.contains(argName) { continue }

            // For required arguments in non-TTY environment
            guard self.hasTTY || arg.defaultValue != nil || arg.isOptional else {
                throw TemplateError.missingRequiredArgument(argName)
            }

            let value: [String] = if let defaultValue = arg.defaultValue, !hasTTY {
                // use default value if in a non-TTY environment
                [defaultValue]
            } else if arg.isOptional, !self.hasTTY {
                ["nil"]
            } else {
                // Prompt for required argument
                try self.promptUserForArgument(arg)
            }

            // if argument is optional, and user wanted to explicitly unset, they would have written nil, which resolves
            // to index 0
            if arg.isOptional && value[0] == "nil" {
                responses.append(ArgumentResponse(
                    argument: arg,
                    values: value,
                    isExplicitlyUnset: true
                ))
            } else {
                responses.append(ArgumentResponse(
                    argument: arg,
                    values: value,
                    isExplicitlyUnset: false
                ))
            }
        }

        return responses
    }

    public func promptUserForArgument(_ argument: ArgumentInfoV0) throws -> [String] {
        let argName = try getArgumentName(argument)
        let promptMessage = "\(argument.abstract ?? argName)"

        switch argument.kind {
        case .flag:
            return try ["\(String(describing: self.promptForFlag(argument, promptMessage: promptMessage)))"]
        case .option:
            return try self.promptForOption(argument, promptMessage: promptMessage)
        case .positional:
            // For single positional prompting, assume position 1 of 1
            return try self.promptForPositional(argument, position: 1, totalPositionals: 1)
        }
    }

    /// Prompts for multiple positional arguments in sequence, respecting position order
    public func promptUserForPositionalArguments(_ arguments: [ArgumentInfoV0]) throws -> [[String]] {
        let positionalArgs = arguments.filter { $0.kind == .positional }
        var results: [[String]] = []

        if positionalArgs.isEmpty {
            return results
        }

        print("Collecting positional arguments (\(positionalArgs.count) total):")
        print()

        for (index, argument) in positionalArgs.enumerated() {
            let position = index + 1
            let values = try promptForPositional(argument, position: position, totalPositionals: positionalArgs.count)
            results.append(values)

            // If this was an optional argument and user skipped it,
            // check if there are later required arguments
            if argument.isOptional && values.isEmpty {
                let laterArgs = Array(positionalArgs[(index + 1)...])
                let hasLaterRequired = laterArgs.contains { !$0.isOptional }

                if hasLaterRequired {
                    print("Skipping optional argument. Cannot prompt for later required arguments.")
                    break
                }
            }

            print() // Spacing between arguments
        }

        return results
    }

    private func promptForPostionalArgument(
        _: ArgumentInfoV0,
        promptMessage: String
    ) throws -> String {
        ""
    }

    /// Interactive prompting for positional arguments with strategy-aware behavior
    private func promptForPositional(
        _ argument: ArgumentInfoV0,
        position: Int,
        totalPositionals: Int
    ) throws -> [String] {
        let argName = argument.valueName ?? "argument"
        let isRequired = !argument.isOptional

        // Build context-aware prompt message
        var promptHeader = "Argument \(position)/\(totalPositionals): \(argument.abstract ?? argName)"

        if !isRequired {
            promptHeader += " (optional)"
        }

        // Handle different parsing strategies with appropriate prompting
        switch argument.parsingStrategy {
        case .allRemainingInput:
            return try self.promptForPassthroughPositional(argument, header: promptHeader)

        case .postTerminator:
            return try self.promptForPostTerminatorPositional(argument, header: promptHeader)

        case .allUnrecognized:
            throw TemplateError.unsupportedParsingStrategy

        case .default, .scanningForValue, .unconditional, .upToNextOption:
            // Standard positional argument prompting
            return try self.promptForStandardPositional(argument, header: promptHeader)
        }
    }

    /// Prompts for standard positional arguments (most common case)
    private func promptForStandardPositional(_ argument: ArgumentInfoV0, header: String) throws -> [String] {
        let isRequired = !argument.isOptional
        let hasDefault = argument.defaultValue != nil

        if argument.isRepeating {
            // Repeating positional argument
            print(header)
            if let defaultValue = argument.defaultValue {
                print("Default: \(defaultValue)")
            }

            if let allowedValues = argument.allValues {
                print("Allowed values: \(allowedValues.joined(separator: ", "))")
            }

            print("Enter multiple values (one per line, empty line to finish):")

            var values: [String] = []
            while true {
                print("[\(values.count)] > ", terminator: "")
                guard let input = readLine() else {
                    break
                }

                if input.isEmpty {
                    break // Empty line finishes collection
                }

                // Validate input
                if let allowedValues = argument.allValues, !allowedValues.contains(input) {
                    print("Invalid value '\(input)'. Allowed values: \(allowedValues.joined(separator: ", "))")
                    continue
                }

                values.append(input)
                print("Added '\(input)' (total: \(values.count))")
            }

            // Handle empty collection
            if values.isEmpty {
                if let defaultValue = argument.defaultValue {
                    return [defaultValue]
                } else if !isRequired {
                    return []
                } else {
                    throw TemplateError.missingRequiredArgument(header)
                }
            }

            return values

        } else {
            // Single positional argument
            var promptSuffix = ""
            if hasDefault, let defaultValue = argument.defaultValue {
                promptSuffix = " (default: \(defaultValue))"
            } else if !isRequired {
                promptSuffix = " (press Enter to skip)"
            }

            if let allowedValues = argument.allValues {
                print("\(header)")
                print("Allowed values: \(allowedValues.joined(separator: ", "))")
                print("Enter value\(promptSuffix): ", terminator: "")
            } else {
                print("\(header)\(promptSuffix): ", terminator: "")
            }

            guard let input = readLine() else {
                if hasDefault, let defaultValue = argument.defaultValue {
                    return [defaultValue]
                } else if !isRequired {
                    return []
                } else {
                    throw TemplateError.missingRequiredArgument(header)
                }
            }

            if input.isEmpty {
                if hasDefault, let defaultValue = argument.defaultValue {
                    return [defaultValue]
                } else if !isRequired {
                    return []
                } else {
                    throw TemplateError.missingRequiredArgument(header)
                }
            }

            // Validate input
            if let allowedValues = argument.allValues, !allowedValues.contains(input) {
                print("Invalid value '\(input)'. Allowed values: \(allowedValues.joined(separator: ", "))")
                throw TemplateError.invalidArgumentValue(
                    value: input,
                    argument:
                    header
                )
            }

            return [input]
        }
    }

    /// Prompts for .allRemainingInput (passthrough) arguments
    private func promptForPassthroughPositional(
        _ argument: ArgumentInfoV0,
        header: String
    ) throws -> [String] {
        print(header)
        print("This argument captures ALL remaining input as-is (including flags and options)")
        print("Everything you enter will be passed through without parsing.")
        print("Enter the complete argument string: ", terminator: "")

        guard let input = readLine() else {
            if argument.isOptional {
                return []
            } else {
                throw TemplateError.missingRequiredArgument(header)
            }
        }

        if input.isEmpty {
            if argument.isOptional {
                return []
            } else {
                throw TemplateError.missingRequiredArgument(header)
            }
        }

        // Split input into individual arguments (respecting quotes)
        return self.splitCommandLineString(input)
    }

    /// Prompts for .postTerminator arguments
    private func promptForPostTerminatorPositional(
        _: ArgumentInfoV0,
        header: String
    ) throws -> [String] {
        print(header)
        print("This argument only captures values that appear after '--' separator")
        print("Enter arguments as they would appear after '--': ", terminator: "")

        guard let input = readLine() else {
            return []
        }

        if input.isEmpty {
            return []
        }

        return self.splitCommandLineString(input)
    }

    /// Utility to split a command line string into individual arguments
    /// Handles basic quoting (simplified version)
    private func splitCommandLineString(_ input: String) -> [String] {
        var arguments: [String] = []
        var currentArg = ""
        var inQuotes = false
        var quoteChar: Character? = nil

        for char in input {
            switch char {
            case "\"", "'":
                if !inQuotes {
                    inQuotes = true
                    quoteChar = char
                } else if char == quoteChar {
                    inQuotes = false
                    quoteChar = nil
                } else {
                    currentArg.append(char)
                }
            case " ", "\t":
                if inQuotes {
                    currentArg.append(char)
                } else if !currentArg.isEmpty {
                    arguments.append(currentArg)
                    currentArg = ""
                }
            default:
                currentArg.append(char)
            }
        }

        if !currentArg.isEmpty {
            arguments.append(currentArg)
        }

        return arguments
    }

    private func promptForOption(
        _ argument: ArgumentInfoV0,
        promptMessage:
        String
    ) throws -> [String] {
        let prefix = promptMessage
        var suffix = ""

        if argument.defaultValue == nil && argument.isOptional {
            suffix = " or enter \"nil\" to unset."
        } else if let defaultValue = argument.defaultValue {
            suffix = " (default: \(defaultValue))"
        }

        if let allValues = argument.allValues {
            suffix += " (allowed values: \(allValues.joined(separator: ", ")))"
        }

        if argument.isRepeating {
            // For repeating arguments, show clear instructions
            print("\(prefix)\(suffix)")
            print("Enter multiple values (one per line, empty line to finish):")

            var values: [String] = []
            while true {
                print("> ", terminator: "")
                guard let input = readLine() else {
                    break
                }

                if input.isEmpty {
                    break // Empty line finishes collection
                }

                if input.lowercased() == "nil" && argument.isOptional {
                    return ["nil"]
                }

                // Validate input and retry on error
                if let allowed = argument.allValues, !allowed.contains(input) {
                    print("Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))")
                    print("Please try again:")
                    continue
                }

                values.append(input)
                print("Added '\(input)' (total: \(values.count))")
            }

            if values.isEmpty {
                if let defaultValue = argument.defaultValue {
                    return [defaultValue]
                }
                return []
            }
            return values

        } else {
            // For single arguments
            let completeMessage = prefix + suffix
            print(completeMessage, terminator: " ")

            guard let input = readLine() else {
                if let defaultValue = argument.defaultValue {
                    return [defaultValue]
                }
                return []
            }

            if input.isEmpty {
                if let defaultValue = argument.defaultValue {
                    return [defaultValue]
                }
                return []
            }

            if input.lowercased() == "nil" && argument.isOptional {
                return ["nil"]
            }

            if let allowed = argument.allValues, !allowed.contains(input) {
                let argName = argument.preferredName?.name ?? argument.names?.first?.name ?? argument.valueName ?? "unknown"
                print("Invalid value '\(input)'. Allowed values: \(allowed.joined(separator: ", "))")
                throw TemplateError.invalidArgumentValue(value: input, argument: argName)
            }

            return [input]
        }
    }

    private func promptForFlag(_ argument: ArgumentInfoV0, promptMessage: String) throws -> Bool? {
        let defaultBehaviour: Bool? = if let defaultValue = argument.defaultValue {
            defaultValue.lowercased() == "true"
        } else {
            nil
        }

        var suffix: String = if let defaultBehaviour {
            defaultBehaviour ? " [Y/n]" : " [y/N]"
        } else {
            " [y/n]"
        }

        let isOptional = argument.isOptional
        if isOptional && defaultBehaviour == nil {
            suffix = suffix + " or enter \"nil\" to unset."
        }

        print(promptMessage + suffix, terminator: " ")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            // Handle EOF/no input
            if let defaultBehaviour {
                return defaultBehaviour
            } else if isOptional {
                return nil
            } else {
                throw TemplateError.missingRequiredArgument(argument.preferredName?.name ?? "unknown")
            }
        }

        switch input {
        case "y", "yes", "true", "1":
            return true
        case "n", "no", "false", "0":
            return false
        case "nil":
            if isOptional {
                return nil
            } else {
                let argName = argument.preferredName?.name ?? "unknown"
                throw TemplateError.invalidArgumentValue(value: input, argument: argName)
            }
        case "":
            // Empty input - use default or handle as missing
            if let defaultBehaviour {
                return defaultBehaviour
            } else if isOptional {
                return nil
            } else {
                throw TemplateError.missingRequiredArgument(argument.preferredName?.name ?? "unknown")
            }
        default:
            // Invalid input - provide clear error
            let argName = argument.preferredName?.name ?? "unknown"
            print("Invalid value '\(input)'. Please enter: y/yes/true, n/no/false" + (isOptional ? ", or nil" : ""))
            throw TemplateError.invalidArgumentValue(value: input, argument: argName)
        }
    }

    public func promptForSubcommandSelection(_ subcommands: [CommandInfoV0]) throws -> CommandInfoV0 {
        guard self.hasTTY else {
            throw TemplateError.noTTYForSubcommandSelection
        }

        print("Available subcommands:")
        for (index, subcommand) in subcommands.enumerated() {
            print("\(index + 1). \(subcommand.commandName)")
        }

        print("Select subcommand (number or name): ", terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty
        else {
            throw TemplateError.invalidSubcommandSelection(validOptions: nil)
        }

        // Try to parse as index first
        if let choice = Int(input),
           choice > 0 && choice <= subcommands.count
        {
            return subcommands[choice - 1]
        }

        // Try to find by name (exact match)
        if let matchedSubcommand = subcommands.first(where: { $0.commandName ==
                input
        }) {
            return matchedSubcommand
        }

        // Try to find by name (case-insensitive match)
        if let matchedSubcommand = subcommands.first(where: { $0.commandName.lowercased() == input.lowercased() }) {
            return matchedSubcommand
        }

        let validOptions = subcommands.map(\.commandName).joined(separator: ", ")
        throw TemplateError.invalidSubcommandSelection(validOptions: validOptions)
    }

    public func promptForAmbiguousSubcommand(_ command: String, _ branches: [CommandInfoV0]) throws -> CommandInfoV0 {
        guard self.hasTTY else {
            throw TemplateError.ambiguousSubcommand(command: command, branches: branches.map(\.commandName))
        }

        print("Command '\(command)' found in multiple branches:")
        for (index, branch) in branches.enumerated() {
            print("\(index + 1). \(branch.commandName)")
        }

        print("Select branch (1-\(branches.count)): ", terminator: "")

        guard let input = readLine(),
              let choice = Int(input),
              choice > 0 && choice <= branches.count
        else {
            throw TemplateError.invalidSubcommandSelection(validOptions: nil)
        }

        return branches[choice - 1]
    }

    private func getArgumentName(_ argument: ArgumentInfoV0) throws -> String {
        guard let name = argument.valueName ?? argument.preferredName?.name else {
            throw ParsingStringError("Argument has no name")
        }
        return name
    }
}
