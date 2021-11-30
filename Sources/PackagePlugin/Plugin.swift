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

// The way in which SwiftPM communicates with the plugin is an implementation
// detail, but the way it currently works is that the plugin is compiled (in
// a very similar way to the package manifest) and then run in a sandbox.
//
// Currently the plugin input is provided in the form of a JSON-encoded input
// structure passed as the last command line argument; however, this will very
// likely change so that it is instead passed on `stdin` of the process that
// runs the plugin, since that avoids any command line length limitations.
//
// Any generated commands and diagnostics are emitted on `stdout` after a zero
// byte; this allows regular output, such as print statements for debugging,
// to be emitted to SwiftPM verbatim. SwiftPM tries to interpret any stdout
// contents after the last zero byte as a JSON encoded output struct in UTF-8
// encoding; any failure to decode it is considered a protocol failure.
//
// The exit code of the compiled plugin determines success or failure (though
// failure to decode the output is also considered a failure to run the ex-
// tension).

extension Plugin {
    
    public static func main(_ arguments: [String]) throws {
        // Look for the input JSON as the last argument of the invocation.
        guard let inputData = ProcessInfo.processInfo.arguments.last?.data(using: .utf8) else {
            fputs("Expected last argument to contain JSON input data in UTF-8 encoding, but didn't find it.", stderr)
            Diagnostics.error("Expected last argument to contain JSON input data in UTF-8 encoding, but didn't find it.")
            exit(1)
        }

        // Deserialize the input JSON.
        let input = try PluginInput(from: inputData)
        
        // Construct a PluginContext from the deserialized input.
        let context = PluginContext(
            package: input.package,
            pluginWorkDirectory: input.pluginWorkDirectory,
            builtProductsDirectory: input.builtProductsDirectory,
            toolNamesToPaths: input.toolNamesToPaths)
        
        // Instantiate the plugin. For now there are no parameters, but this is
        // where we would set them up, most likely as properties of the plugin
        // instance (in a manner similar to SwiftArgumentParser).
        let plugin = self.init()
        
        // Invoke the appropriate protocol method, based on the plugin action
        // that SwiftPM specified.
        let commands: [Command]
        switch input.pluginAction {
        case .createBuildToolCommands(let target):
            // Check that the plugin implements the appropriate protocol for its
            // declared capability.
            guard let plugin = plugin as? BuildToolPlugin else {
                throw PluginDeserializationError.malformedInputJSON("Plugin declared with `buildTool` capability but doesn't conform to `BuildToolPlugin` protocol")
            }
            
            // Ask the plugin to create build commands for the input target.
            commands = try plugin.createBuildCommands(context: context, target: target)
        }
        
        // Construct the output structure to send to SwiftPM.
        let output = try PluginOutput(commands: commands, diagnostics: Diagnostics.emittedDiagnostics)

        // On stdout, write a zero byte followed by the JSON data — this is what libSwiftPM expects to see. Anything before the last zero byte is treated as freeform output from the plugin (such as debug output from `print` statements). Since `FileHandle.write()` doesn't obey buffering we first have to flush any existing output.
        fputc(0, stdout)
        fwrite([UInt8](output.outputData), 1, output.outputData.count, stdout)
    }
    
    public static func main() throws {
        try self.main(CommandLine.arguments)
    }
}
