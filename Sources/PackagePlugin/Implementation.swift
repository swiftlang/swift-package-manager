/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@_implementationOnly import Foundation

// The way in which SwiftPM communicates with the package plugin is an im-
// plementation detail, but the way it currently works is that the plugin
// is compiled (in a very similar way to the package manifest) and then run in
// a sandbox. Currently it is passed the JSON encoded input structure as the
// last command line argument; however, it this will likely change to instead
// read it from stdin, since that avoids any command line length limitation.
// Any generated commands and diagnostics are emitted on stdout after a zero
// byte; this allows regular output, such as print statements for debugging,
// to be emitted to SwiftPM verbatim. SwiftPM tries to interpret any stdout
// contents after the last zero byte as a JSON encoded output struct in UTF-8
// encoding; any failure to decode it is considered a protocol failure. The
// exit code of the compiled plugin determines success or failure (though
// failure to decode the output is also considered a failure to run the ex-
// tension).

extension Plugin {

    public static func main() throws {
        // Look for the input JSON as the last argument of the invocation.
        guard let inputData = ProcessInfo.processInfo.arguments.last?.data(using: .utf8) else {
            fputs("Expected last argument to contain JSON input data in UTF-8 encoding, but didn't find it.", stderr)
            output.diagnostics.append(Diagnostic(severity: .error, message: "Expected last argument to contain JSON input data in UTF-8 encoding, but didn't find it.", file: nil, line: nil))
            exit(1)
        }
 
        // Decode the input JSON into a plugin context.
        let context: TargetBuildContext
        do {
            let decoder = JSONDecoder()
            context = try decoder.decode(TargetBuildContext.self, from: inputData)
        }
        catch {
            fputs("Couldn't decode input JSON (reason: \(error)", stderr)
            output.diagnostics.append(Diagnostic(severity: .error, message: "\(error)", file: nil, line: nil))
            exit(1)
        }

        // Instantiate the plugin. For now there are no parameters, but this is where we would set them up, most likely as properties of the plugin.
        let plugin = self.init()
        
        // Invoke the appropriate protocol method based on the action.
        switch context.pluginAction {
        case .createBuildToolCommands:
            // Check that the plugin conforms to `BuildToolPlugin`, and get the commands.
            guard let plugin = plugin as? BuildToolPlugin else {
                throw PluginDeserializationError.malformedInputJSON("Plugin declared with `buildTool` capability but doesn't conform to `BuildToolPlugin` protocol")
            }
            let commands = try plugin.createBuildCommands(context: context)
            
            // Convert the commands to the encodable output representation SwiftPM currently expects.
            output.buildCommands = commands.compactMap {
                guard case let ._buildCommand(displayName, executable, arguments, environment, workingDir, inputFiles, outputFiles) = $0 else { return .none }
                return BuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDir, inputFiles: inputFiles, outputFiles: outputFiles)
            }
            output.prebuildCommands = commands.compactMap {
                guard case let ._prebuildCommand(displayName, executable, arguments, environment, workingDir, outputFilesDir) = $0 else { return .none }
                return PrebuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDir, outputFilesDirectory: outputFilesDir)
            }
        }

        // Encoding the output struct from the plugin for SwiftPM to read.
        let encoder = JSONEncoder()
        let outputData = try! encoder.encode(output)
        
        // On stdout, write a zero byte followed by the JSON data — this is what libSwiftPM expects to see. Anything before the last zero byte is treated as freeform output from the plugin (such as debug output from `print` statements). Since `FileHandle.write()` doesn't obey buffering we first have to flush any existing output.
        fputc(0, stdout)
        fwrite([UInt8](outputData), 1, outputData.count, stdout)
    }
}

/// Private structures containing the information to send back to SwiftPM.

struct BuildCommand: Encodable {
    let displayName: String?
    let executable: Path
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: Path?
    let inputFiles: [Path]
    let outputFiles: [Path]
}

struct PrebuildCommand: Encodable {
    let displayName: String?
    let executable: Path
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: Path?
    let outputFilesDirectory: Path
}

struct Diagnostic: Encodable {
    let severity: Diagnostics.Severity
    let message: String
    let file: Path?
    let line: Int?
}

struct OutputStruct: Encodable {
    let version: Int
    var diagnostics: [Diagnostic] = []
    var buildCommands: [BuildCommand] = []
    var prebuildCommands: [PrebuildCommand] = []
}

var output = OutputStruct(version: 1)

public enum PluginDeserializationError: Error {
    /// The input JSON is malformed in some way; the message provides more details.
    case malformedInputJSON(_ message: String)
}

extension PluginDeserializationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .malformedInputJSON(let message):
            return "Malformed input JSON: \(message)"
        }
    }
}
