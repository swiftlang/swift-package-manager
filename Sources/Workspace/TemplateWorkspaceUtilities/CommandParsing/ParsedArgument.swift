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

/// Represents a single parsed command-line argument token from a template CLI.
///
/// `ParsedTemplateArgument` encapsulates the original token string along with
/// its parsed type (short flag, short option, grouped short flags, long flag, or long option),
/// and provides convenience properties and methods for inspection and matching.
struct ParsedTemplateArgument: Equatable {
    /// The type of the parsed argument.
    enum ArgumentType: Equatable {
        /// A single-character short flag, e.g., `-f`
        case shortFlag(Character)

        /// A single-character short option, e.g., `-o value` or `-o=value`
        case shortOption(Character, String?)

        /// A group of short flags combined, e.g., `-abc`
        case shortGroup([Character])

        /// A long-form flag, e.g., `--force`
        case longFlag(String)

        /// A long-form option, e.g., `--output=value` or `--output value`
        case longOption(String, String?)
    }

    /// The parsed type of this argument.
    let type: ArgumentType

    /// The original token string from the command-line input.
    let originalToken: String

    /// The canonical name of the argument
    var name: String {
        switch self.type {
        case .shortFlag(let character), .shortOption(let character, _):
            String(character)
        case .shortGroup(let characters):
            String(characters.first ?? "?")
        case .longFlag(let name), .longOption(let name, _):
            name
        }
    }

    /// The associated value of the argument if it is an option, or `nil` otherwise.
    var value: String? {
        switch self.type {
        case .shortOption(_, let value), .longOption(_, let value):
            value
        default:
            nil
        }
    }

    /// Returns `true` if this is a short-form argument (single dash), `false` otherwise.
    var isShort: Bool {
        switch self.type {
        case .shortFlag, .shortOption, .shortGroup:
            true
        case .longFlag, .longOption:
            false
        }
    }

    /// Checks if this argument matches a given name.
    ///
    /// - Parameter targetName: The name to compare against.
    /// - Returns: `true` if the argument's name matches `targetName`.
    func matchesName(_ targetName: String) -> Bool {
        self.name == targetName
    }

    // MARK: - Parsing Methods

    /// Parses a long-form argument token (e.g., `--option=value` or `--flag`) into a `ParsedTemplateArgument`.
    ///
    /// - Parameter remainder: The string following the `--` prefix.
    /// - Returns: A `ParsedTemplateArgument` representing the long option or flag.
    /// - Throws: Parsing errors if the format is invalid.
    static func parseLongOption(_ remainder: String) throws ->
        ParsedTemplateArgument
    {
        if let equalIndex = remainder.firstIndex(of: "=") {
            let name = String(remainder[..<equalIndex])
            let value = String(remainder[remainder.index(after: equalIndex)...])
            return ParsedTemplateArgument(
                type: .longOption(name, value),
                originalToken: "--\(remainder)"
            )
        } else {
            // Default to treating as option without value (will consume next token)
            // The actual flag vs option determination will happen during argument matching
            return ParsedTemplateArgument(
                type: .longOption(remainder, nil),
                originalToken: "--\(remainder)"
            )
        }
    }

    /// Parses short-form argument tokens (e.g., `-f`, `-abc`, `-o=value`) into one or more `ParsedTemplateArgument`s.
    ///
    /// - Parameter remainder: The string following the `-` prefix.
    /// - Returns: An array of parsed short flags or options.
    /// - Throws: Parsing errors if the format is invalid.
    static func parseShortOptions(_ remainder: String) throws ->
        [ParsedTemplateArgument]
    {
        if let equalIndex = remainder.firstIndex(of: "=") {
            // -o=value format
            let name = String(remainder[..<equalIndex])
            let value = String(remainder[remainder.index(after: equalIndex)...])
            guard name.count == 1, let char = name.first else {
                throw ParsingStringError("Invalid short option format")
            }
            return [ParsedTemplateArgument(
                type: .shortOption(char, value),
                originalToken: "-\(remainder)"
            )]
        } else if remainder.count == 1 {
            // Single short option: -f
            guard let char = remainder.first else {
                throw ParsingStringError("Empty short option")
            }
            return [ParsedTemplateArgument(
                type: .shortFlag(char),
                originalToken: "-\(remainder)"
            )]
        } else {
            // Multiple short options: -abc or -ovalue
            let chars = Array(remainder)
            return chars.map { char in
                ParsedTemplateArgument(
                    type: .shortFlag(char),
                    originalToken: "-\(remainder)"
                )
            }
        }
    }
}
