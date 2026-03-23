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
import Foundation

/// `TemplateCLIConstructor` attempts to parse a set of predefined arguments for a CLI tool
/// described by `ToolInfoV0`. If parsing fails and a TTY (interactive terminal) is available,
/// it falls back to interactive prompting to gather the required arguments from the user.
public class TemplateCLIConstructor {
    /// Indicates whether a TTY (interactive terminal) is available.
    private let hasTTY: Bool
    /// Optional scope for emitting debug and warning messages during parsing.
    private let observabilityScope: ObservabilityScope?

    /// Creates a new `TemplateCLIConstructor`.
    ///
    /// - Parameters:
    ///   - hasTTY: A boolean indicating if a TTY is available for interactive prompting.
    ///   - observabilityScope: An optional observability scope for emitting logs and debug messages.
    public init(hasTTY: Bool, observabilityScope: ObservabilityScope? = nil) {
        self.hasTTY = hasTTY
        self.observabilityScope = observabilityScope
    }

    /// Attempts to create a finalized command-line from predefined arguments.
    ///
    /// This method first tries to parse the provided `predefinedArgs` using a template parser.
    /// If parsing fails and a TTY is available, it will fall back to interactively prompting
    /// the user for all required arguments.
    ///
    /// - Parameters:
    ///   - predefinedArgs: An array of predefined command-line arguments to parse.
    ///   - toolInfoJson: Argument tree of the CLI tool in `ToolInfoV0` format.
    /// - Returns: An array of command-line arguments constructed either from `predefinedArgs`
    ///            or from interactive user input.
    /// - Throws: Rethrows any parsing errors if parsing fails and a TTY is unavailable.
    public func createCLIArgs(predefinedArgs: [String], toolInfoJson: ToolInfoV0)
        throws -> [String]
    {
        self.observabilityScope?
            .emit(
                debug: "Starting template argument parsing with predefined args: [\(predefinedArgs.joined(separator: ", "))]"
            )

        // we are now at the top, we have access to the root command
        var parser = TemplateCommandParser(toolInfoJson.command, observabilityScope: self.observabilityScope)

        do {
            // First attempt: try parsing with predefined arguments
            self.observabilityScope?.emit(debug: "Attempting to parse predefined arguments")
            let commandPath = try parser.parseWithPrompting(predefinedArgs, hasTTY: self.hasTTY)
            let result = self.buildCommandLine(from: commandPath)
            self.observabilityScope?
                .emit(debug: "Successfully parsed template arguments, result: [\(result.joined(separator: ", "))]")
            return result
        } catch {
            self.observabilityScope?
                .emit(warning: "Initial template argument parsing failed: \(self.formatErrorMessage(error))")
            // On parsing failure, implement fallback strategy
            return try self.handleParsingError(error, toolInfoJson: toolInfoJson, predefinedArgs: predefinedArgs)
        }
    }

    /// Handles parsing errors and falls back to interactive prompting if a TTY is available.
    ///
    /// If no TTY is available, this method rethrows the original parsing error.
    ///
    /// - Parameters:
    ///   - error: The original error thrown during parsing.
    ///   - toolInfoJson: Metadata about the CLI tool.
    ///   - predefinedArgs: The arguments that were initially provided.
    /// - Returns: A list of arguments collected interactively from the user.
    /// - Throws: Rethrows the original parsing error if no TTY is available or if interactive parsing fails.
    private func handleParsingError(
        _ error: Error,
        toolInfoJson: ToolInfoV0,
        predefinedArgs: [String]
    ) throws -> [String] {
        self.observabilityScope?.emit(debug: "Handling parsing error, checking TTY availability")

        // If no TTY available, re-throw the original error
        guard self.hasTTY else {
            self.observabilityScope?.emit(debug: "No TTY available, re-throwing original error")
            throw error
        }

        self.observabilityScope?.emit(debug: "TTY available, falling back to interactive prompting")

        self.observabilityScope?
            .emit(info: "Parsing failed with predefined arguments:  \(predefinedArgs.joined(separator: " "))")
        self.observabilityScope?.emit(info: "Error: \(self.formatErrorMessage(error))")
        self.observabilityScope?.emit(info: " Prompting for all arguments")

        // Cancel all predefined inputs and prompt for everything from scratch
        self.observabilityScope?.emit(debug: "Creating fresh parser for interactive prompting")
        var freshParser = TemplateCommandParser(toolInfoJson.command, observabilityScope: self.observabilityScope)
        let commandPath = try freshParser.parseWithPrompting([], hasTTY: self.hasTTY)
        let result = self.buildCommandLine(from: commandPath)
        self.observabilityScope?
            .emit(debug: "Interactive parsing completed successfully, result: [\(result.joined(separator: ", "))]")
        return result
    }

    /// Formats an error into a human-readable string.
    ///
    /// - Parameter error: The error to format.
    /// - Returns: A descriptive string explaining the error.
    private func formatErrorMessage(_ error: Error) -> String {
        switch error {
        case let templateError as TemplateError:
            self.formatTemplateError(templateError)
        case let parsingError as ParsingError:
            self.formatParsingError(parsingError)
        default:
            error.localizedDescription
        }
    }

    /// Formats a `TemplateError` into a human-readable message.
    ///
    /// - Parameter error: The template error to format.
    /// - Returns: A descriptive string for the template error.
    private func formatTemplateError(_ error: TemplateError) -> String {
        switch error {
        case .unexpectedArguments(let args):
            "Unexpected arguments: \(args.joined(separator: ", "))"
        case .ambiguousSubcommand(let command, let branches):
            "Ambiguous subcommand '\(command)' found in: \(branches.joined(separator: ", "))"
        case .noTTYForSubcommandSelection:
            "Interactive subcommand selection requires a terminal"
        case .missingRequiredArgument(let name):
            "Missing required argument: \(name)"
        case .invalidArgumentValue(let value, let arg):
            "Invalid value '\(value)' for argument '\(arg)'"
        case .invalidSubcommandSelection(let validOptions):
            "Invalid subcommand selection. Please select a valid index or  write a valid subcommand name \(validOptions ?? "")"
        case .unsupportedParsingStrategy:
            "Unsupported parsing strategy"
        }
    }

    /// Formats a `ParsingError` into a human-readable message.
    ///
    /// - Parameter error: The parsing error to format.
    /// - Returns: A descriptive string for the parsing error.
    private func formatParsingError(_ error: ParsingError) -> String {
        switch error {
        case .missingValueForOption(let option):
            "Missing value for option '--\(option)'"
        case .invalidValue(let arg, let invalid, let allowed):
            if allowed.isEmpty {
                "Invalid value '\(invalid.joined(separator: ", "))' for '\(arg)'"
            } else {
                "Invalid value '\(invalid.joined(separator: ", "))' for '\(arg)'. Valid options: \(allowed.joined(separator: ", "))"
            }
        case .tooManyValues(let arg, let expected, let received):
            "Too many values for '\(arg)' (expected \(expected), got \(received))"
        case .unexpectedArgument(let arg):
            "Unexpected argument: \(arg)"
        case .multipleParsingErrors(let errors):
            "Multiple parsing errors: \(errors.map(\.localizedDescription).joined(separator: ", "))"
        }
    }

    /// Builds the final command-line argument list from a parsed `TemplateCommandPath`.
    ///
    /// - Parameter commandPath: The parsed command chain containing commands and their arguments.
    /// - Returns: An array of strings representing the full CLI invocation.
    private func buildCommandLine(from commandPath: TemplateCommandPath) ->
        [String]
    {
        var result: [String] = []

        for (index, component) in commandPath.commandChain.enumerated() {
            // Skip root command name, but include subcommand names
            if index > 0 {
                result.append(component.commandName)
            }

            // Add all arguments for this command level
            for argument in component.arguments {
                result.append(contentsOf: argument.commandLineFragments)
            }
        }

        return result
    }
}
