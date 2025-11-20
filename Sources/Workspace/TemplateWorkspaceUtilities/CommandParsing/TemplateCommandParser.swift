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
import class Basics.ObservabilityScope
import Foundation

public struct TemplateCommandParser {
    let rootCommand: CommandInfoV0
    var currentCommand: CommandInfoV0
    var parsedCommands: [CommandComponent] = []
    var commandStack: [CommandInfoV0] = []
    private var parsingErrors: [ParsingError] = []
    private let observabilityScope: ObservabilityScope?

    init(_ rootCommand: CommandInfoV0, observabilityScope: ObservabilityScope? = nil) {
        self.rootCommand = rootCommand
        self.currentCommand = rootCommand
        self.commandStack = [rootCommand]
        self.observabilityScope = observabilityScope
    }

    mutating func parseWithPrompting(_ arguments: [String], hasTTY: Bool) throws -> TemplateCommandPath {
        self.observabilityScope?
            .emit(debug: "Parsing template arguments: [\(arguments.joined(separator: ", "))] with TTY: \(hasTTY)")
        var split = try SplitArguments(arguments: arguments)

        while true {
            self.observabilityScope?.emit(debug: "Processing command: '\(self.currentCommand.commandName)'")

            // 1. Parse available arguments for current command
            let parsingResult = try parseAvailableArguments(&split)

            if !parsingResult.errors.isEmpty {
                self.observabilityScope?
                    .emit(
                        warning: "Parsing errors encountered for command '\(self.currentCommand.commandName)': \(parsingResult.errors.map(\.localizedDescription).joined(separator: ", "))"
                    )
            }

            // 2. Prompt for missing required arguments (if TTY available)
            let prompter = TemplatePrompter(hasTTY: hasTTY)
            let parsedArgNames = Set(parsingResult.responses.compactMap { try? self.getArgumentName($0.argument) })

            self.observabilityScope?
                .emit(
                    debug: "Prompting for missing arguments. Already parsed: [\(parsedArgNames.joined(separator: ", "))]"
                )
            let promptedResponses = try
                prompter.promptForMissingArguments(self.currentCommand.arguments ?? [], parsed: parsedArgNames)

            // 3. Combine all responses
            let allResponses = parsingResult.responses + promptedResponses
            let validatedResponses = try validateAllResponses(allResponses)

            // 4. Create command component
            let component = CommandComponent(
                commandName: currentCommand.commandName,
                arguments: validatedResponses
            )
            self.parsedCommands.append(component)
            self.observabilityScope?
                .emit(
                    debug: "Added command component: '\(self.currentCommand.commandName)' with \(validatedResponses.count) arguments"
                )

            // 5. Look for subcommand
            guard let nextCommand = try consumeNextSubcommand(&split, hasTTY: hasTTY) else {
                break // No more subcommands
            }

            self.currentCommand = nextCommand
            self.commandStack.append(nextCommand)
        }

        // Validate no unexpected arguments remain
        let remainingElements = split.unconsumedElements
        if !remainingElements.isEmpty && !remainingElements.allSatisfy(\.isTerminator) {
            let remaining = remainingElements.compactMap { element -> String? in
                switch element.value {
                case .value(let str): return str
                case .option(let opt): return "--\(opt.name)"
                case .terminator: return nil
                }
            }

            if !remaining.isEmpty {
                self.observabilityScope?
                    .emit(warning: "Found unexpected arguments: [\(remaining.joined(separator: ", "))]")
                throw TemplateError.unexpectedArguments(remaining)
            }
        }

        // Report any collected parsing errors if no other errors occurred
        if !self.parsingErrors.isEmpty {
            self.observabilityScope?
                .emit(
                    warning: "Multiple parsing errors occurred: \(self.parsingErrors.map(\.localizedDescription).joined(separator: ", "))"
                )
            throw ParsingError.multipleParsingErrors(self.parsingErrors)
        }

        let fullPathKey = self.parsedCommands.map(\.commandName).joined(separator: "-")
        self.observabilityScope?
            .emit(
                debug: "Successfully parsed template command path: '\(fullPathKey)' with \(self.parsedCommands.count) command components"
            )

        return TemplateCommandPath(
            fullPathKey: fullPathKey,
            commandChain: self.parsedCommands
        )
    }

    private mutating func parseAvailableArguments(_ split: inout SplitArguments)
        throws -> ParsingResult
    {
        guard let arguments = currentCommand.arguments else {
            self.observabilityScope?
                .emit(debug: "No arguments defined for command '\(self.currentCommand.commandName)'")
            return ParsingResult(responses: [], errors: [], remainingArguments: [])
        }

        self.observabilityScope?
            .emit(
                debug: "Parsing \(arguments.count) available arguments for command '\(self.currentCommand.commandName)'"
            )

        var responses: [ArgumentResponse] = []
        var parsedArgNames: Set<String> = []
        var localErrors: [ParsingError] = []

        // handle postTerminator arguments first (before any parsing)
        do {
            let postTerminatorResponses = try
                parsePostTerminatorArguments(arguments, &split)
            responses.append(contentsOf: postTerminatorResponses)
            for response in responses {
                try parsedArgNames.insert(self.getArgumentName(response.argument))
            }
            if !postTerminatorResponses.isEmpty {
                self.observabilityScope?
                    .emit(debug: "Parsed \(postTerminatorResponses.count) post-terminator arguments")
            }
        } catch {
            if let parsingError = error as? ParsingError {
                self.observabilityScope?
                    .emit(warning: "Post-terminator argument parsing failed: \(parsingError.localizedDescription)")
                localErrors.append(parsingError)
            }
        }

        // Parsed named arguments and regular positionals
        self.parseNamedAndPositionalArguments(
            &split,
            arguments,
            &responses,
            &parsedArgNames,
            &localErrors
        )

        self.parsingErrors.append(contentsOf: localErrors)

        if !localErrors.isEmpty {
            self.observabilityScope?
                .emit(debug: "Collected \(localErrors.count) parsing errors during argument processing")
        }

        return ParsingResult(
            responses: responses,
            errors: localErrors,
            remainingArguments: split.remainingValues
        )
    }

    private mutating func parseNamedAndPositionalArguments(
        _ split: inout SplitArguments,
        _ arguments: [ArgumentInfoV0],
        _ responses: inout [ArgumentResponse],
        _ parsedArgNames: inout Set<String>,
        _ localErrors: inout [ParsingError]
    ) {
        // Check for passthrough capture behavior
        let capturesForPassthrough = arguments.contains { arg in
            arg.kind == .positional &&
                arg.parsingStrategy == .allRemainingInput &&
                arg.isRepeating
        }

        argumentLoop: while let element = split.peekNext(), !element.isTerminator {
            switch element.value {
            case .option(let parsed):
                do {
                    if case .shortGroup(let characters) = parsed.type {
                        // Expand shortGroup into individual flags
                        let element = split.consumeNext()!
                        var shouldStopParsing = false

                        for char in characters {
                            let expandedFlag = ParsedTemplateArgument(
                                type: .shortFlag(char), originalToken:
                                parsed.originalToken
                            )
                            if let matchedArg = findMatchingArgument(expandedFlag, in: arguments) {
                                let argName = try getArgumentName(matchedArg)
                                split.markAsConsumed(
                                    element.index,
                                    for:
                                    .optionValue(argName),
                                    argumentName: argName
                                )
                                let response = try
                                    parseOptionWithValidation(matchedArg, expandedFlag, &split)
                                responses.append(response)
                                parsedArgNames.insert(argName)
                            } else {
                                // Check if this short flag might belong to a subcommand
                                if self.isPotentialSubcommandOption(String(char)) {
                                    self.observabilityScope?
                                        .emit(
                                            debug: "Short option '-\(char)' might belong to subcommand, stopping current level parsing"
                                        )
                                    shouldStopParsing = true
                                    break argumentLoop // Stop processing this flag group
                                }

                                self.observabilityScope?.emit(warning: "Unknown option '-\(char)' encountered")
                                localErrors.append(.unexpectedArgument("-\(char)"))
                                split.markAsConsumed(
                                    element.index,
                                    for:
                                    .subcommand,
                                    argumentName: "-\(char)"
                                )
                            }
                        }

                        if shouldStopParsing {
                            break argumentLoop // Exit main parsing loop
                        }
                    } else {
                        if let matchedArg = findMatchingArgument(
                            parsed,
                            in: arguments
                        ) {
                            let argName = try getArgumentName(matchedArg)
                            let element = split.consumeNext()!
                            // Consume the option element itself first

                            split.markAsConsumed(
                                element.index,
                                for:
                                .optionValue(argName),
                                argumentName: argName
                            )
                            let response = try parseOptionWithValidation(matchedArg, parsed, &split)
                            responses.append(response)
                            parsedArgNames.insert(argName)
                        } else {
                            // Unknown option - check if it could belong to a subcommand
                            if capturesForPassthrough {
                                break argumentLoop // Stop for passthrough
                            }

                            // Check if this option might belong to a subcommand
                            if self.isPotentialSubcommandOption(parsed.name) {
                                self.observabilityScope?
                                    .emit(
                                        debug: "Option '--\(parsed.name)' might belong to subcommand, stopping current level parsing"
                                    )
                                break argumentLoop // Stop parsing at this level, leave for subcommand
                            }

                            self.observabilityScope?.emit(warning: "Unknown option '--\(parsed.name)' encountered")
                            localErrors.append(.unexpectedArgument("--\(parsed.name)"))
                            let element = split.consumeNext()!
                            // Consume to avoid infinite loop
                            split.markAsConsumed(element.index, for: .subcommand, argumentName: "--\(parsed.name)")
                        }
                    }
                } catch {
                    if let parsingError = error as? ParsingError {
                        localErrors.append(parsingError)
                    }
                    _ = split.consumeNext() // Continue parsing
                }

            case .value(let value):
                // Check for passthrough capture at first unrecognized value
                if capturesForPassthrough {
                    let hasMatchingPositional = (try?
                        self.getNextPositionalArgument(arguments, parsedArgNames)
                    ) != nil
                    if !hasMatchingPositional && !self.isPotentialSubcommand(value) {
                        break argumentLoop// Stop parsing for passthrough
                    }
                }

                // Check if this could be part of a subcommand path
                if self.isPotentialSubcommand(value) {
                    break argumentLoop // Leave for subcommand processing
                }

                // Try to match with positional arguments
                do {
                    if let positionalArg = try
                        getNextPositionalArgument(arguments, parsedArgNames)
                    {
                        if positionalArg.parsingStrategy == .allRemainingInput {
                            let response = try
                                parseAllRemainingInputPositional(positionalArg, value, &split)
                            responses.append(response)
                            try parsedArgNames.insert(
                                self.getArgumentName(positionalArg)
                            )
                            break argumentLoop
                            // allRemainingInput consumes everything, stop parsing
                        } else {
                            let response = try
                                parseRegularPositional(positionalArg, value, &split)
                            responses.append(response)
                            try parsedArgNames.insert(
                                self.getArgumentName(positionalArg)
                            )
                        }
                    } else {
                        localErrors.append(.unexpectedArgument(value))
                        self.observabilityScope?
                            .emit(
                                warning: "Unexpected positional argument '\(value)' - no matching positional parameter found"
                            )
                        let element = split.consumeNext()!
                        // Consume to avoid infinite loop
                        split.markAsConsumed(element.index, for: .subcommand, argumentName: value)
                        break argumentLoop
                        // No more positional arguments to fill
                    }
                } catch {
                    if let parsingError = error as? ParsingError {
                        localErrors.append(parsingError)
                    }
                    _ = split.consumeNext() // Continue parsing
                }

            case .terminator:
                break argumentLoop // Skip terminator, already handled in Phase 1
            }
        }
    }

    private mutating func validateAllResponses(_ responses: [ArgumentResponse])
        throws -> [ArgumentResponse]
    {
        self.observabilityScope?.emit(debug: "Validating \(responses.count) argument responses")
        var validatedResponses: [ArgumentResponse] = []
        var validationErrors: [ParsingError] = []

        for response in responses {
            do {
                try self.validateParsedArgument(response)
                validatedResponses.append(response)
            } catch {
                // Collect validation errors but continue
                if let parsingError = error as? ParsingError {
                    self.observabilityScope?
                        .emit(warning: "Validation failed for argument: \(parsingError.localizedDescription)")
                    validationErrors.append(parsingError)
                    self.parsingErrors.append(parsingError)
                }
                // Include response anyway for partial parsing
                validatedResponses.append(response)
            }
        }

        if !validationErrors.isEmpty {
            self.observabilityScope?
                .emit(
                    debug: "Validation completed with \(validationErrors.count) errors, \(validatedResponses.count) responses processed"
                )
        } else {
            self.observabilityScope?
                .emit(debug: "All \(validatedResponses.count) argument responses validated successfully")
        }

        return validatedResponses
    }

    private func validateParsedArgument(_ response: ArgumentResponse) throws {
        let arg = response.argument
        let argName = try getArgumentName(arg)

        // Validate value count
        if !arg.isRepeating && response.values.count > 1 {
            throw ParsingError.tooManyValues(argName, 1, response.values.count)
        }

        // Validate against allowed values
        if let allowedValues = arg.allValues, !allowedValues.isEmpty {
            let invalidValues = response.values.filter {
                !allowedValues.contains($0)
            }
            if !invalidValues.isEmpty {
                throw ParsingError.invalidValue(
                    argName,
                    invalidValues,
                    allowedValues
                )
            }
        }

        // Validate completion constraints
        if let completionKind = arg.completionKind,
           case .list(let allowedValues) = completionKind
        {
            let invalidValues = response.values.filter {
                !allowedValues.contains($0)
            }
            if !invalidValues.isEmpty {
                throw ParsingError.invalidValue(
                    argName,
                    invalidValues,
                    allowedValues
                )
            }
        }
    }

    private func parseOptionWithValidation(
        _ arg: ArgumentInfoV0,
        _ parsed: ParsedTemplateArgument,
        _ split: inout SplitArguments
    ) throws -> ArgumentResponse {
        let argName = try getArgumentName(arg)

        switch arg.kind {
        case .flag:
            // Flags should not have values
            if parsed.value != nil {
                throw ParsingError.unexpectedArgument("Flag \(argName) should not have a value")
            }
            return ArgumentResponse(
                argument: arg,
                values: ["true"],
                isExplicitlyUnset: false
            )

        case .option:
            var values: [String] = []

            switch arg.parsingStrategy {
            case .default:
                if let attachedValue = parsed.value {
                    values = [attachedValue]
                } else {
                    guard let nextValue = split.consumeNextValue(for: argName)
                    else {
                        throw ParsingError.missingValueForOption(argName)
                    }
                    values = [nextValue]
                }

            case .scanningForValue:
                if let attachedValue = parsed.value {
                    values = [attachedValue]
                } else if let scannedValue = split.scanForNextValue(for: argName) {
                    values = [scannedValue]
                } else if let defaultValue = arg.defaultValue,
                          !requiresPrompting(for: arg)
                {
                    values = [defaultValue]
                }

            case .unconditional:
                if let attachedValue = parsed.value {
                    values = [attachedValue]
                } else {
                    guard let nextElement = split.consumeNext() else {
                        throw ParsingError.missingValueForOption(argName)
                    }

                    switch nextElement.value {
                    case .value(let value):
                        values = [value]
                    case .option(let opt):
                        values = ["--\(opt.name)"]
                    case .terminator:
                        values = ["--"]
                    }
                }

            case .upToNextOption:
                if let attachedValue = parsed.value {
                    values = [attachedValue]
                }

                while let nextValue = split.consumeNextValue(for: argName) {
                    values.append(nextValue)
                }

                if values.isEmpty, let defaultValue = arg.defaultValue,
                   !requiresPrompting(for: arg)
                {
                    values = [defaultValue]
                }

            case .allRemainingInput:
                if let attachedValue = parsed.value {
                    values = [attachedValue]
                }

                while let element = split.consumeNext() {
                    switch element.value {
                    case .value(let value):
                        values.append(value)
                    case .option(let opt):
                        values.append("--\(opt.name)")
                        if let optValue = opt.value {
                            values.append(optValue)
                        }
                    case .terminator:
                        values.append("--")
                    }
                }

            case .postTerminator, .allUnrecognized:
                throw ParsingError.unexpectedArgument("Positional parsing strategy used for option \(argName)")
            }

            // Handle repeating arguments by continuing to parse if needed
            if arg.isRepeating && values.count == 1 {
                // Could continue parsing more values based on strategy
                // Implementation depends on specific requirements
            }

            return ArgumentResponse(
                argument: arg,
                values: values,
                isExplicitlyUnset: false
            )

        case .positional:
            throw ParsingError.unexpectedArgument("Positional argument parsing should be handled separately")
        }
    }

    private func parsePostTerminatorArguments(
        _ arguments: [ArgumentInfoV0],
        _ split: inout SplitArguments
    ) throws -> [ArgumentResponse] {
        var responses: [ArgumentResponse] = []

        let postTerminatorArgs = arguments.filter {
            $0.kind == .positional && $0.parsingStrategy == .postTerminator
        }

        guard !postTerminatorArgs.isEmpty else { return responses }

        // Use enhanced method that properly removes consumed elements
        let postTerminatorValues = split.removeElementsAfterTerminator()

        if let firstPostTerminatorArg = postTerminatorArgs.first,
           !postTerminatorValues.isEmpty
        {
            responses.append(ArgumentResponse(
                argument: firstPostTerminatorArg,
                values: postTerminatorValues,
                isExplicitlyUnset: false
            ))
        }

        return responses
    }

    private func isHelpArgument(_ arg: ArgumentInfoV0) -> Bool {
        let argName = (try? self.getArgumentName(arg)) ?? ""
        return argName.lowercased() == "help" ||
            arg.names?.contains { $0.name.lowercased() == "help" } == true
    }

    private func requiresPrompting(for arg: ArgumentInfoV0) -> Bool {
        // Determine if this argument should be prompted for rather than using default
        // This could be based on argument metadata, current context, etc.
        !arg.isOptional && arg.defaultValue == nil
    }

    private func isSubcommand(_ value: String) -> Bool {
        self.currentCommand.subcommands?.contains { $0.commandName == value } ??
            false
    }

    private func findMatchingArgument(
        _ parsed: ParsedTemplateArgument,
        in arguments: [ArgumentInfoV0]
    ) -> ArgumentInfoV0? {
        arguments.first { arg in
            guard let names = arg.names else { return false }
            return names.contains { nameInfo in
                if parsed.isShort {
                    nameInfo.kind == .short && nameInfo.name ==
                        parsed.name
                } else {
                    nameInfo.kind == .long && nameInfo.name == parsed.name
                }
            }
        }
    }

    private func getArgumentName(_ argument: ArgumentInfoV0) throws -> String {
        guard let name = argument.valueName ?? argument.preferredName?.name else {
            throw ParsingStringError("NO NAME BAD")
        }
        return name
    }

    private func getNextPositionalArgument(
        _ arguments: [ArgumentInfoV0],
        _ parsedArgNames: Set<String>
    ) throws -> ArgumentInfoV0? {
        try arguments.first { arg in
            try arg.kind == .positional &&
                !parsedArgNames.contains(self.getArgumentName(arg))
        }
    }

    private func parseRegularPositional(
        _ arg: ArgumentInfoV0,
        _ value: String,
        _ split: inout
            SplitArguments
    ) throws ->
        ArgumentResponse
    {
        // Consume the current value
        let argName = try getArgumentName(arg)
        let element = split.consumeNext()!
        split.markAsConsumed(
            element.index,
            for: .positionalArgument(argName),
            argumentName: argName
        )

        var values = [value]

        // If repeating, consume additional values until next option/subcommand
        if arg.isRepeating {
            while let nextValue = split.consumeNextValue(for: arg.preferredName?.name) {
                values.append(nextValue)
            }
        }

        return ArgumentResponse(
            argument: arg,
            values: values,
            isExplicitlyUnset:
            false
        )
    }

    private func parseAllRemainingInputPositional(
        _ arg: ArgumentInfoV0,
        _ value: String,
        _ split: inout SplitArguments
    ) throws -> ArgumentResponse {
        var values = [value]

        // Consume the current value first
        _ = split.consumeNext()

        // Then consume EVERYTHING remaining (including options as values)
        while let element = split.consumeNext() {
            switch element.value {
            case .value(let str):
                values.append(str)
            case .option(let opt):
                values.append("--\(opt.name)")
                if let optValue = opt.value {
                    values.append(optValue)
                }
            case .terminator:
                values.append("--")
            }
        }

        return ArgumentResponse(argument: arg, values: values, isExplicitlyUnset: false)
    }

    private func getSubCommand(from command: CommandInfoV0) -> [CommandInfoV0]? {
        guard let subcommands = command.subcommands else { return nil }
        let filteredSubcommands = subcommands.filter {
            $0.commandName.lowercased() != "help"
        }
        guard !filteredSubcommands.isEmpty else { return nil }
        return filteredSubcommands
    }

    private func isPotentialSubcommand(_ value: String) -> Bool {
        self.findSubcommandPath(value, from: self.currentCommand) != nil
    }

    private func isPotentialSubcommandOption(_ optionName: String) -> Bool {
        guard let subcommands = currentCommand.subcommands else { return false }

        // Recursively check if any subcommand has this option
        return self.hasOptionInSubcommands(optionName, subcommands: subcommands)
    }

    private func hasOptionInSubcommands(_ optionName: String, subcommands: [CommandInfoV0]) -> Bool {
        for subcommand in subcommands {
            // Check if this subcommand has the option
            if let arguments = subcommand.arguments {
                for arg in arguments {
                    if let names = arg.names {
                        for nameInfo in names {
                            if (nameInfo.kind == .long && nameInfo.name == optionName) ||
                                (nameInfo.kind == .short && nameInfo.name == optionName)
                            {
                                return true
                            }
                        }
                    }
                }
            }

            // Recursively check nested subcommands
            if let nestedSubcommands = subcommand.subcommands,
               hasOptionInSubcommands(optionName, subcommands: nestedSubcommands)
            {
                return true
            }
        }

        return false
    }

    private func findSubcommandPath(_ targetCommand: String, from command: CommandInfoV0) -> [String]? {
        guard let subcommands = command.subcommands else { return nil }

        // Check direct subcommands
        for subcommand in subcommands {
            if subcommand.commandName == targetCommand {
                return [subcommand.commandName]
            }

            // Check nested subcommands
            if let nestedPath = findSubcommandPath(
                targetCommand,
                from:
                subcommand
            ) {
                return [subcommand.commandName] + nestedPath
            }
        }

        return nil
    }

    private mutating func consumeNextSubcommand(_ split: inout SplitArguments, hasTTY: Bool) throws -> CommandInfoV0? {
        // No direct subcommand found - check if we need intelligent branch
        guard let subCommands = getSubCommand(from: currentCommand) else {
            self.observabilityScope?.emit(debug: "No Subcommands found")
            return nil // No subcommands available
        }

        // Intelligent branch selection with validation
        if let nextValue = split.peekNext()?.value,
           case .value(let potentialCommand) = nextValue,
           let _ = findSubcommandPath(potentialCommand, from: currentCommand)
        {

            let compatibleBranches = subCommands.filter { branch in
                // First check if this branch IS the command we're looking for
                if branch.commandName == potentialCommand {
                    return true
                }
                // Otherwise check if the command exists within this branch
                return self.findSubcommandPath(potentialCommand, from: branch) != nil
            }

            self.observabilityScope?.emit(debug: "Found compatible branches: \(compatibleBranches.map(\.commandName))")

            if compatibleBranches.count == 1 {
                // Unambiguous - auto-select with notification
                self.observabilityScope?.emit(debug: "Auto-selecting '\(compatibleBranches.first!.commandName)' for command '\(potentialCommand)'")

                // Consume the subcommand token
                let element = split.consumeNext()!
                split.markAsConsumed(element.index, for: .subcommand, argumentName: potentialCommand)

                return compatibleBranches.first!

            } else if compatibleBranches.count > 1 {
                guard hasTTY else {
                    throw TemplateError.ambiguousSubcommand(
                        command: potentialCommand,
                        branches: compatibleBranches.map(\.commandName)
                    )
                }

                // Ambiguous - prompt with context
                print("Command '\(potentialCommand)' found in multiple branches:")
                let prompter = TemplatePrompter(hasTTY: hasTTY)
                let choice = try
                    prompter.promptForAmbiguousSubcommand(potentialCommand, compatibleBranches)

                // Consume the subcommand token
                let element = split.consumeNext()!
                split.markAsConsumed(element.index, for: .subcommand, argumentName: potentialCommand)

                return choice
            }
        }

        // Fallback: Regular branch selection
        guard hasTTY else {
            throw TemplateError.noTTYForSubcommandSelection
        }

        let prompter = TemplatePrompter(hasTTY: hasTTY)
        let chosenBranch = try prompter.promptForSubcommandSelection(subCommands)
        return chosenBranch
    }
}

