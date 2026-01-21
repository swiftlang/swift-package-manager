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

import Foundation

enum TemplateError: Error, Equatable {
    case unexpectedArguments([String])
    case ambiguousSubcommand(command: String, branches: [String])
    case noTTYForSubcommandSelection
    case missingRequiredArgument(String)
    case invalidArgumentValue(value: String, argument: String)
    case invalidSubcommandSelection(validOptions: String?)
    case unsupportedParsingStrategy
}

public enum TestTemplateCommandError: Error, CustomStringConvertible {
    case invalidManifestInTemplate
    case templateNotFound(String)
    case noTemplatesInManifest
    case multipleTemplatesFound([String])
    case directoryCreationFailed(String)
    case buildSystemNotSupported(String)
    case generationFailed(String)
    case buildFailed(String)
    case outputRedirectionFailed(String)
    case invalidUTF8Encoding(Data)

    public var description: String {
        switch self {
        case .invalidManifestInTemplate:
            "Invalid or missing Package.swift manifest found in template. The template must contain a valid Swift package manifest."
        case .templateNotFound(let templateName):
            "Could not find template '\(templateName)' with packageInit options. Verify the template name and ensure it has proper template configuration."
        case .noTemplatesInManifest:
            "No templates with packageInit options were found in the manifest. The package must contain at least one target with template initialization options."
        case .multipleTemplatesFound(let templates):
            "Multiple templates found: \(templates.joined(separator: ", ")). Please specify one using --template-name option."
        case .directoryCreationFailed(let path):
            "Failed to create output directory at '\(path)'. Check permissions and available disk space."
        case .buildSystemNotSupported(let system):
            "Build system '\(system)' is not supported for template testing. Use a supported build system."
        case .generationFailed(let details):
            "Template generation failed: \(details). Check template configuration and input arguments."
        case .buildFailed(let details):
            "Build failed after template generation: \(details). Check generated code and dependencies."
        case .outputRedirectionFailed(let path):
            "Failed to redirect output to log file at '\(path)'. Check file permissions and disk space."
        case .invalidUTF8Encoding(let data):
            "Failed to encode \(data) into UTF-8."
        }
    }
}
