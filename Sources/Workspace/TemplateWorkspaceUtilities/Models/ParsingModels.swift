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

struct ParsingStringError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

struct ParsingResult {
    let responses: [ArgumentResponse]
    let errors: [ParsingError]
    let remainingArguments: [String]
}

enum ParsingError: Error {
    case missingValueForOption(String)
    case invalidValue(String, [String], [String]) // arg, invalid, allowed
    case tooManyValues(String, Int, Int) // arg, expected, received
    case unexpectedArgument(String)
    case multipleParsingErrors([ParsingError])
}

struct ConsumptionRecord {
    let elementIndex: Int
    let purpose: ConsumptionPurpose
    let argumentName: String?
}

enum ConsumptionPurpose {
    case optionValue(String)
    case positionalArgument(String)
    case postTerminator
    case subcommand
}
