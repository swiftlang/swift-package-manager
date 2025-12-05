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

enum TemplateError: Error, Equatable {
    case unexpectedArguments([String])
    case ambiguousSubcommand(command: String, branches: [String])
    case noTTYForSubcommandSelection
    case missingRequiredArgument(String)
    case invalidArgumentValue(value: String, argument: String)
    case invalidSubcommandSelection(validOptions: String?)
    case unsupportedParsingStrategy
}
