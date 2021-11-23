/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_implementationOnly import Foundation
#if os(Windows)
@_implementationOnly import ucrt
#endif

//
// This source file contains the main entry point for all plugins. It decodes
// input from SwiftPM, determines which protocol function to call, and finally
// encodes output for SwiftPM.
//
// The specifics of how SwiftPM communicates with the plugin are implementation
// details, but the way it currently works is that the plugin is compiled as an
// executable and then run in a sandbox that blocks network access and prevents
// changes to all except a few file system locations.
//
// The "plugin host" (SwiftPM or an IDE using libSwiftPM) sends a JSON-encoded
// context struct to the plugin process on its original standard-input pipe, and
// when finished, the plugin sends a JSON-encoded result struct back to the host
// on its original standard-output pipe. The plugin host treats output on the
// standard-error pipe as free-form output text from the plugin (for debugging
// purposes, etc).

// Within the plugin process, `stdout` is redirected to `stderr` so that print
// statements from the plugin are treated as plain-text output, and `stdin` is
// closed so that attemps by the plugin logic to read from console input return
// errors instead of blocking. The original `stdin` and `stdout` are duplicated
// for use as messaging pipes, and are not directly used by the plugin logic.
//
// Using the standard input and output streams avoids having to make allowances
// in the sandbox for other channels of communication, and seems a more portable
// approach than many of the alternatives.
//
// The exit code of the plugin process determines whether the plugin invocation
// is considered successful. A failure result should also be accompanied by an
// emitted error diagnostic, so that errors are understandable by the user.
//

extension Plugin {
    
    /// Main entry point of the plugin — sets up a communication channel with
    /// the plugin host and runs the main message loop.
    public static func main() throws {
        // Duplicate the `stdin` file descriptor, which we will then use as an
        // input stream from which we receive messages from the plugin host.
        let inputFD = dup(fileno(stdin))
        guard inputFD >= 0 else {
            internalError("Could not duplicate `stdin`: \(describe(errno: errno)).")
        }
        
        // Having duplicated the original standard-input descriptor, we close
        // `stdin` so that attempts by the plugin to read console input (which
        // are usually a mistake) return errors instead of blocking.
        guard close(fileno(stdin)) >= 0 else {
            internalError("Could not close `stdin`: \(describe(errno: errno)).")
        }

        // Duplicate the `stdout` file descriptor, which we will then use as an
        // output stream to which we send messages to the plugin host.
        let outputFD = dup(fileno(stdout))
        guard outputFD >= 0 else {
            internalError("Could not dup `stdout`: \(describe(errno: errno)).")
        }
        
        // Having duplicated the original standard-output descriptor, redirect
        // `stdout` to `stderr` so that all free-form text output goes there.
        guard dup2(fileno(stderr), fileno(stdout)) >= 0 else {
            internalError("Could not dup2 `stdout` to `stderr`: \(describe(errno: errno)).")
        }
        
        // Turn off full buffering so printed text appears as soon as possible.
        setlinebuf(stdout)
        
        // Open a message channel for communicating with the plugin host.
        pluginHostConnection = PluginHostConnection(
            inputStream: FileHandle(fileDescriptor: inputFD),
            outputStream: FileHandle(fileDescriptor: outputFD))
        
        // Process messages from the host until the input stream is closed,
        // indicating that we're done.
        while let message = try pluginHostConnection.waitForNextMessage() {
            try handleMessage(message)
        }
    }
    
    fileprivate static func handleMessage(_ message: HostToPluginMessage) throws {
        switch message {
        // Invokes an action defined in the input JSON. This is an interim
        // message to bridge to the old logic; this will be separateed out
        // into different messages for different plugin capabilities, etc.
        // This will let us avoid the double encoded JSON.
        case .performAction(let wireInput):
            // Decode the plugin input structure. We'll resolve this doubly
            // encoded JSON in an upcoming change.
            let inputStruct: PluginInput
            do {
                inputStruct = try PluginInput(from: wireInput)
            } catch {
                internalError("Couldn’t decode input JSON: \(error).")
            }
            
            // Construct a PluginContext from the deserialized input.
            let context = PluginContext(
                package: inputStruct.package,
                pluginWorkDirectory: inputStruct.pluginWorkDirectory,
                builtProductsDirectory: inputStruct.builtProductsDirectory,
                toolNamesToPaths: inputStruct.toolNamesToPaths)
            
            // Instantiate the plugin. For now there are no parameters, but
            // this is where we would set them up, most likely as properties
            // of the plugin instance (similar to how SwiftArgumentParser
            // allows commands to annotate arguments). It could use property
            // wrappers to mark up properties in the plugin.
            let plugin = self.init()
            
            // Invoke the appropriate protocol method, based on the plugin
            // action that SwiftPM specified.
            let generatedCommands: [Command]
            switch inputStruct.pluginAction {
                
            case .createBuildToolCommands(let target):
                // Check that the plugin implements the appropriate protocol
                // for its declared capability.
                guard let plugin = plugin as? BuildToolPlugin else {
                    throw PluginDeserializationError.malformedInputJSON("Plugin declared with `buildTool` capability but doesn't conform to `BuildToolPlugin` protocol")
                }
                
                // Ask the plugin to create build commands for the target.
                generatedCommands = try plugin.createBuildCommands(context: context, target: target)
                
            case .performCommand(let targets, let arguments):
                // Check that the plugin implements the appropriate protocol
                // for its declared capability.
                guard let plugin = plugin as? CommandPlugin else {
                    throw PluginDeserializationError.malformedInputJSON("Plugin declared with `command` capability but doesn't conform to `CommandPlugin` protocol")
                }
                
                // Invoke the plugin.
                try plugin.performCommand(context: context, targets: targets, arguments: arguments)
                
                // For command plugin there are currently no return commands
                // (any commands invoked by the plugin are invoked directly).
                generatedCommands = []
            }
            
            // Send back the output data (a JSON-encoded struct) to the plugin host.
            let outputStruct: PluginOutput
            do {
                outputStruct = try PluginOutput(commands: generatedCommands, diagnostics: Diagnostics.emittedDiagnostics)
            } catch {
                internalError("Couldn’t encode output JSON: \(error).")
            }
            try pluginHostConnection.sendMessage(.provideResult(output: outputStruct.output))
            
        default:
            internalError("unexpected top-level message \(message)")
        }
    }

    // Private function to report internal errors and then exit.
    fileprivate static func internalError(_ message: String) -> Never {
        fputs("Internal Error: \(message)", stderr)
        exit(1)
    }
    
    // Private function to construct an error message from an `errno` code.
    fileprivate static func describe(errno: Int32) -> String {
        if let cStr = strerror(errno) { return String(cString: cStr) }
        return String(describing: errno)
    }
}

/// Message channel for communicating with the plugin host.
internal fileprivate(set) var pluginHostConnection: PluginHostConnection!


/// A message that the host can send to the plugin.
enum HostToPluginMessage: Decodable {
    case performAction(input: WireInput)
}

/// A message that the plugin can send to the host.
enum PluginToHostMessage: Encodable {
    case provideResult(output: WireOutput)
}


typealias PluginHostConnection = MessageConnection<PluginToHostMessage, HostToPluginMessage>

struct MessageConnection<TX,RX> where TX: Encodable, RX: Decodable {
    let inputStream: FileHandle
    let outputStream: FileHandle

    func sendMessage(_ message: TX) throws {
        // Encode the message as JSON.
        let payload = try JSONEncoder().encode(message)
        
        // Write the header (a 64-bit length field in little endian byte order).
        var count = UInt64(littleEndian: UInt64(payload.count))
        let header = Swift.withUnsafeBytes(of: &count) { Data($0) }
        assert(header.count == 8)
        try outputStream.write(contentsOf: header)

        // Write the payload.
        try outputStream.write(contentsOf: payload)
    }
    
    func waitForNextMessage() throws -> RX? {
        // Read the header (a 64-bit length field in little endian byte order).
        guard let header = try inputStream.read(upToCount: 8) else { return nil }
        guard header.count == 8 else {
            throw PluginMessageError.truncatedHeader
        }
        
        // Decode the count.
        let count = header.withUnsafeBytes{ $0.load(as: UInt64.self).littleEndian }
        guard count >= 2 else {
            throw PluginMessageError.invalidPayloadSize
        }

        // Read the JSON payload.
        guard let payload = try inputStream.read(upToCount: Int(count)), payload.count == count else {
            throw PluginMessageError.truncatedPayload
        }

        // Decode and return the message.
        return try JSONDecoder().decode(RX.self, from: payload)
    }

    enum PluginMessageError: Swift.Error {
        case truncatedHeader
        case invalidPayloadSize
        case truncatedPayload
    }
}
