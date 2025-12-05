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

struct ParsedTemplateArgument: Equatable {
    enum ArgumentType: Equatable {
        case shortFlag(Character)
        case shortOption(Character, String?)
        case shortGroup([Character])
        case longFlag(String)
        case longOption(String, String?)
    }

    let type: ArgumentType
    let originalToken: String

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

    var value: String? {
        switch self.type {
        case .shortOption(_, let value), .longOption(_, let value):
            value
        default:
            nil
        }
    }

    var isShort: Bool {
        switch self.type {
        case .shortFlag, .shortOption, .shortGroup:
            true
        case .longFlag, .longOption:
            false
        }
    }

    func matchesName(_ targetName: String) -> Bool {
        self.name == targetName
    }

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

            // Check if it could be -ovalue format (option with joined value)
            // This requires looking at argument definitions to determine
            // For now, treat as group of flags
            return chars.map { char in
                ParsedTemplateArgument(
                    type: .shortFlag(char),
                    originalToken: "-\(remainder)"
                )
            }
        }
    }
}

