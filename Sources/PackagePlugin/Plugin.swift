/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/*
   This source file contains the main entry point for all plugins. It decodes
   input from SwiftPM, determines which protocol function to call, and finally
   encodes output for SwiftPM.
*/

@_implementationOnly import Foundation
#if os(Windows)
@_implementationOnly import ucrt    // for stdio functions
#endif

// The way in which SwiftPM communicates with the plugin is an implementation
// detail, but the way it currently works is that the plugin is compiled (in
// a very similar way to the package manifest) and then run in a sandbox.
//
// Currently the plugin input is provided in the form of a JSON-encoded input
// structure passed as the last command line argument; however, this will very
// likely change so that it is instead passed on `stdin` of the process that
// runs the plugin, since that avoids any command line length limitations.
//
// An output structure containing any generated commands and diagnostics is
// passed back to SwiftPM on `stdout`. All freeform output from the plugin
// is redirected to `stderr`, which SwiftPM shows to the user without inter-
// preting it in any way.
//
// The exit code of the compiled plugin determines success or failure (though
// failure to decode the output is also considered a failure to run the ex-
// tension).

extension Plugin {
    
    public static func main(_ arguments: [String]) throws {
        
        // Use the initial `stdout` for returning JSON, and redirect `stdout`
        // to `stderr` for capturing freeform text.
        let jsonOut = fdopen(dup(fileno(stdout)), "w")
        dup2(fileno(stderr), fileno(stdout))
        
        // Close `stdin` to avoid blocking if the plugin tries to read input.
        close(fileno(stdin))

        // Private function for reporting internal errors and halting execution.
        func internalError(_ message: String) -> Never {
            Diagnostics.error("Internal Error: \(message)")
            fputs("Internal Error: \(message)", stderr)
            exit(1)
        }
        
        // Look for the input JSON as the last argument of the invocation.
        guard let inputData = ProcessInfo.processInfo.arguments.last?.data(using: .utf8) else {
            internalError("Expected last argument to contain JSON input data in UTF-8 encoding, but didn't find it.")
        }
        
        // Deserialize the input JSON.
        let input: PluginInput
        do {
            input = try PluginInput(from: inputData)
        } catch {
            internalError("Couldn’t decode input JSON: \(error).")
        }
        
        // Construct a PluginContext from the deserialized input.
        let context = PluginContext(
            package: input.package,
            pluginWorkDirectory: input.pluginWorkDirectory,
            builtProductsDirectory: input.builtProductsDirectory,
            toolNamesToPaths: input.toolNamesToPaths)
        
        // Instantiate the plugin. For now there are no parameters, but this is
        // where we would set them up, most likely as properties of the plugin
        // instance (in a manner similar to SwiftArgumentParser). This would
        // use property wrappers to mark up properties in the plugin.
        let plugin = self.init()
        
        // Invoke the appropriate protocol method, based on the plugin action
        // that SwiftPM specified.
        let generatedCommands: [Command]
        switch input.pluginAction {
            
        case .createBuildToolCommands(let target):
            // Check that the plugin implements the appropriate protocol for its
            // declared capability.
            guard let plugin = plugin as? BuildToolPlugin else {
                throw PluginDeserializationError.malformedInputJSON("Plugin declared with `buildTool` capability but doesn't conform to `BuildToolPlugin` protocol")
            }
            
            // Ask the plugin to create build commands for the input target.
            generatedCommands = try plugin.createBuildCommands(context: context, target: target)
            
        case .performCommand(let targets, let arguments):
            // Check that the plugin implements the appropriate protocol for its
            // declared capability.
            guard let plugin = plugin as? CommandPlugin else {
                throw PluginDeserializationError.malformedInputJSON("Plugin declared with `command` capability but doesn't conform to `CommandPlugin` protocol")
            }
            
            // Invoke the plugin.
            try plugin.performCommand(context: context, targets: targets, arguments: arguments)

            // For command plugin there are currently no return commands (any
            // commands invoked by the plugin are invoked directly).
            generatedCommands = []
        }
        
        // Construct the output structure to send back to SwiftPM.
        let output: PluginOutput
        do {
            output = try PluginOutput(commands: generatedCommands, diagnostics: Diagnostics.emittedDiagnostics)
        } catch {
            internalError("Couldn’t encode output JSON: \(error).")
        }

        // On stdout, write a zero byte followed by the JSON data — this is what libSwiftPM expects to see. Anything before the last zero byte is treated as freeform output from the plugin (such as debug output from `print` statements). Since `FileHandle.write()` doesn't obey buffering we first have to flush any existing output.
        if fwrite([UInt8](output.outputData), 1, output.outputData.count, jsonOut) != output.outputData.count {
            internalError("Couldn’t write output JSON: \(strerror(errno).map{ String(cString: $0) } ?? String(describing: errno)).")
        }
    }
    
    public static func main() throws {
        try self.main(CommandLine.arguments)
    }
}
