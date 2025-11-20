//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParserToolInfo
import Foundation
import Basics

public class TemplateCLIConstructor {
    private let hasTTY: Bool
    private let observabilityScope: ObservabilityScope?

    public init(hasTTY: Bool, observabilityScope: ObservabilityScope? = nil) {
        self.hasTTY = hasTTY
        self.observabilityScope = observabilityScope
    }

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

        // Print the parsing error to inform the user what went wrong
        print("Parsing failed with predefined arguments:  \(predefinedArgs.joined(separator: " "))")
        print("Error: \(self.formatErrorMessage(error))")
        print("\nFalling back to interactive prompting for all arguments...\n")

        // Cancel all predefined inputs and prompt for everything from scratch
        self.observabilityScope?.emit(debug: "Creating fresh parser for interactive prompting")
        var freshParser = TemplateCommandParser(toolInfoJson.command, observabilityScope: self.observabilityScope)
        let commandPath = try freshParser.parseWithPrompting([], hasTTY: self.hasTTY)
        // Empty predefined args

        let result = self.buildCommandLine(from: commandPath)
        self.observabilityScope?
            .emit(debug: "Interactive parsing completed successfully, result: [\(result.joined(separator: ", "))]")
        return result
    }

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

