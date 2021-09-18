/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@_implementationOnly import Foundation

/// Output information from the plugin, for encoding as JSON to send back to
/// SwiftPM. The output structure is currently much simpler than the input
/// (which is actually a directed acyclic graph), and can be directly encoded.
struct PluginOutput {
    let outputData: Data
    
    public init(commands: [Command], diagnostics: [Diagnostic]) throws {
        // Construct a `WireOutput` struture containing the information that
        // SwiftPM expects.
        var output = WireOutput()
        
        // Create the serialized form of any build commands and prebuild commands.
        output.buildCommands = commands.compactMap {
            guard case let ._buildCommand(name, exec, args, env, workDir, inputs, outputs) = $0 else { return nil }
            return .init(displayName: name, executable: exec.string, arguments: args, environment: env, workingDirectory: workDir.map{ $0.string }, inputFiles: inputs.map{ $0.string }, outputFiles: outputs.map{ $0.string })
        }
        output.prebuildCommands = commands.compactMap {
            guard case let ._prebuildCommand(name, exec, args, env, workDir, outputDir) = $0 else { return nil }
            return .init(displayName: name, executable: exec.string, arguments: args, environment: env, workingDirectory: workDir.map{ $0.string }, outputFilesDirectory: outputDir.string)
        }

        // Create the serialized form of any diagnostics.
        output.diagnostics = diagnostics.map {
            switch $0.severity {
            case .error:
                return .init(severity: .error, message: $0.message, file: $0.file?.string, line: $0.line)
            case .warning:
                return .init(severity: .warning, message: $0.message, file: $0.file?.string, line: $0.line)
            case .remark:
                return .init(severity: .remark, message: $0.message, file: $0.file?.string, line: $0.line)
            }
        }
        
        // Encode the output structure to JSON, and keep it around until asked.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.outputData = try encoder.encode(output)
    }
}



/// The output structure sent as JSON to SwiftPM. This structure is currently
/// much simpler than the input structure (which is a directed acyclic graph).
fileprivate struct WireOutput: Encodable {
    var buildCommands: [BuildCommand] = []
    var prebuildCommands: [PrebuildCommand] = []
    var diagnostics: [Diagnostic] = []

    struct BuildCommand: Encodable {
        let displayName: String?
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String?
        let inputFiles: [String]
        let outputFiles: [String]
    }

    struct PrebuildCommand: Encodable {
        let displayName: String?
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String?
        let outputFilesDirectory: String
    }

    struct Diagnostic: Encodable {
        enum Severity: String, Encodable {
            case error, warning, remark
        }
        let severity: Severity
        let message: String
        let file: String?
        let line: Int?
    }
}
