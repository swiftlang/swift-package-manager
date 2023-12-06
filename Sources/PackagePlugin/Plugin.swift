//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_implementationOnly import Foundation
#if os(Windows)
@_implementationOnly import ucrt

internal func dup(_ fd: CInt) -> CInt {
    return _dup(fd)
}
internal func dup2(_ fd1: CInt, _ fd2: CInt) -> CInt {
    return _dup2(fd1, fd2)
}
internal func close(_ fd: CInt) -> CInt {
    return _close(fd)
}
internal func fileno(_ fh: UnsafeMutablePointer<FILE>?) -> CInt {
    return _fileno(fh)
}

internal func strerror(_ errno: CInt) -> String? {
    // MSDN indicates that the returned string can have a maximum of 94
    // characters, so allocate 95 characters.
    return withUnsafeTemporaryAllocation(of: wchar_t.self, capacity: 95) {
        let result = _wcserror_s($0.baseAddress, $0.count, errno)
        guard result == 0, let baseAddress = $0.baseAddress else { return nil }
        return String(decodingCString: baseAddress, as: UTF16.self)
    }
}
#endif

//
// This source file contains the main entry point for all kinds of plugins.
// A plugin receives messages from the "plugin host" (either SwiftPM or some
// IDE that uses libSwiftPM), and sends back messages in return based on its
// actions and events. A plugin can also request services from the host.
//
// Exactly how the plugin host invokes a plugin is an implementation detail,
// but the current approach is to compile the Swift source files that make up
// the plugin into an executable for the host platform, and to then invoke the
// executable in a sandbox that blocks network access and prevents changes to
// all except for a few specific file system locations.
//
// The host process and the plugin communicate using messages in the form of
// length-prefixed JSON-encoded Swift enums. The host sends messages to the
// plugin through its standard-input pipe, and receives messages through the
// plugin's standard-output pipe. All output received through the plugin's
// standard-error pipe is considered to be free-form textual console output.
//
// Within the plugin process, `stdout` is redirected to `stderr` so that print
// statements from the plugin are treated as plain-text output, and `stdin` is
// closed so that any attemps by the plugin logic to read from console result
// in errors instead of blocking the process. The original `stdin` and `stdout`
// are duplicated for use as messaging pipes, and are not directly used by the
// plugin logic.
//
// The exit code of the plugin process indicates whether the plugin invocation
// is considered successful. A failure result should also be accompanied by an
// emitted error diagnostic, so that errors are understandable by the user.
//
// Using standard input and output streams for messaging avoids having to make
// allowances in the sandbox for other channels of communication, and seems a
// more portable approach than many of the alternatives. This is all somewhat
// temporary in any case — in the long term, something like distributed actors
// or something similar can hopefully replace the custom messaging.
//

extension Plugin {
    
    /// Main entry point of the plugin — sets up a communication channel with
    /// the plugin host and runs the main message loop.
    public static func main() async throws {
        // Duplicate the `stdin` file descriptor, which we will then use for
        // receiving messages from the plugin host.
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

        // Duplicate the `stdout` file descriptor, which we will then use for
        // sending messages to the plugin host.
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
        // Windows is much less forgiving than other platforms.  If line
        // buffering is enabled, we must provide a buffer and the size of the
        // buffer.  As a result, on Windows, we completely disable all
        // buffering, which means that partial writes are possible.
#if os(Windows)
        setvbuf(stdout, nil, _IONBF, 0)
#else
        setvbuf(stdout, nil, _IOLBF, 0)
#endif

        // Open a message channel for communicating with the plugin host.
        pluginHostConnection = PluginHostConnection(
            inputStream: FileHandle(fileDescriptor: inputFD),
            outputStream: FileHandle(fileDescriptor: outputFD))
        
        // Handle messages from the host until the input stream is closed,
        // indicating that we're done.
        while let message = try pluginHostConnection.waitForNextMessage() {
            do {
                try await handleMessage(message)
            }
            catch {
                // Emit a diagnostic and indicate failure to the plugin host,
                // and exit with an error code.
                Diagnostics.error(String(describing: error))
                exit(1)
            }
        }
    }
    
    /// Handles a single message received from the plugin host.
    fileprivate static func handleMessage(_ message: HostToPluginMessage) async throws {
        switch message {
            
        case .createBuildToolCommands(let wireInput, let rootPackageId, let targetId):
            // Deserialize the context from the wire input structures. The root
            // package is the one we'll set the context's `package` property to.
            let context: PluginContext
            let target: Target
            do {
                var deserializer = PluginContextDeserializer(wireInput)
                let package = try deserializer.package(for: rootPackageId)
                let pluginWorkDirectory = try deserializer.path(for: wireInput.pluginWorkDirId)
                let toolSearchDirectories = try wireInput.toolSearchDirIds.map {
                    try deserializer.path(for: $0)
                }
                let accessibleTools = try wireInput.accessibleTools.mapValues { (tool: HostToPluginMessage.InputContext.Tool) -> (Path, [String]?) in
                    let path = try deserializer.path(for: tool.path)
                    return (path, tool.triples)
                }

                context = PluginContext(
                    package: package,
                    pluginWorkDirectory: pluginWorkDirectory,
                    accessibleTools: accessibleTools,
                    toolSearchDirectories: toolSearchDirectories)
                target = try deserializer.target(for: targetId)
            }
            catch {
                internalError("Couldn’t deserialize input from host: \(error).")
            }

            // Instantiate the plugin. For now there are no parameters, but
            // this is where we would set them up, most likely as properties
            // of the plugin instance (similar to how SwiftArgumentParser
            // allows commands to annotate arguments). It could use property
            // wrappers to mark up properties in the plugin, and a separate
            // message could be used to query the plugin for its parameter
            // definitions.
            let plugin = self.init()

            // Check that the plugin implements the appropriate protocol
            // for its declared `.buildTool` capability.
            guard let plugin = plugin as? BuildToolPlugin else {
                throw PluginDeserializationError.malformedInputJSON(
                    "Plugin declared with `buildTool` capability but doesn't conform to `BuildToolPlugin` protocol")
            }
            
            // Invoke the plugin to create build commands for the target.
            let generatedCommands = try await plugin.createBuildCommands(context: context, target: target)
            
            // Send each of the generated commands to the host.
            for command in generatedCommands {
                switch command {
                    
                case let ._buildCommand(name, exec, args, env, workdir, inputs, outputs):
                    let command = PluginToHostMessage.CommandConfiguration(
                        displayName: name,
                        executable: exec.string,
                        arguments: args,
                        environment: env,
                        workingDirectory: workdir?.string)
                    let message = PluginToHostMessage.defineBuildCommand(
                        configuration: command,
                        inputFiles: inputs.map{ $0.string },
                        outputFiles: outputs.map{ $0.string })
                    try pluginHostConnection.sendMessage(message)
                    
                case let ._prebuildCommand(name, exec, args, env, workdir, outdir):
                    let command = PluginToHostMessage.CommandConfiguration(
                        displayName: name,
                        executable: exec.string,
                        arguments: args,
                        environment: env,
                        workingDirectory: workdir?.string)
                    let message = PluginToHostMessage.definePrebuildCommand(
                        configuration: command,
                        outputFilesDirectory: outdir.string)
                    try pluginHostConnection.sendMessage(message)
                }
            }
            
            // Exit with a zero exit code to indicate success.
            exit(0)

        case .performCommand(let wireInput, let rootPackageId, let arguments):
            // Deserialize the context from the wire input structures. The root
            // package is the one we'll set the context's `package` property to.
            let context: PluginContext
            do {
                var deserializer = PluginContextDeserializer(wireInput)
                let package = try deserializer.package(for: rootPackageId)
                let pluginWorkDirectory = try deserializer.path(for: wireInput.pluginWorkDirId)
                let toolSearchDirectories = try wireInput.toolSearchDirIds.map {
                    try deserializer.path(for: $0)
                }
                let accessibleTools = try wireInput.accessibleTools.mapValues { (tool: HostToPluginMessage.InputContext.Tool) -> (Path, [String]?) in
                    let path = try deserializer.path(for: tool.path)
                    return (path, tool.triples)
                }
                context = PluginContext(
                    package: package,
                    pluginWorkDirectory: pluginWorkDirectory,
                    accessibleTools: accessibleTools,
                    toolSearchDirectories: toolSearchDirectories)
            }
            catch {
                internalError("Couldn’t deserialize input from host: \(error).")
            }

            // Instantiate the plugin (for now without parameters, as described
            // above).
            let plugin = self.init()

            // Check that the plugin implements the appropriate protocol
            // for its declared `.command` capability.
            guard let plugin = plugin as? CommandPlugin else {
                throw PluginDeserializationError.malformedInputJSON(
                    "Plugin declared with `command` capability but doesn't conform to `CommandPlugin` protocol")
            }
            
            // Invoke the plugin to perform its custom logic.
            try await plugin.performCommand(context: context, arguments: arguments)
            
            // Exit with a zero exit code to indicate success.
            exit(0)
            
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
#if os(Windows)
        return strerror(errno) ?? String(errno)
#else
        if let cStr = strerror(errno) { return String(cString: cStr) }
        return String(describing: errno)
#endif
    }
}

/// Message channel for bidirectional communication with the plugin host.
internal fileprivate(set) var pluginHostConnection: PluginHostConnection!

typealias PluginHostConnection = MessageConnection<PluginToHostMessage, HostToPluginMessage>

internal struct MessageConnection<TX,RX> where TX: Encodable, RX: Decodable {
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
        let count = header.withUnsafeBytes{ $0.loadUnaligned(as: UInt64.self).littleEndian }
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
