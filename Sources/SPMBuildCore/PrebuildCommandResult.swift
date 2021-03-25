/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic


/// Represents the result of running prebuild commands for a single plugin invocation for a target.
public struct PrebuildCommandResult {
    /// Paths of any derived source files that should be included in the build.
    public var derivedSourceFiles: [AbsolutePath]
    
    /// Paths of any directories whose contents influence the build plan.
    public var outputDirectories: [AbsolutePath]
}

/// Runs any prebuild commands associated with the given list of plugin invocation results, in order, and returns the
/// results of running those prebuild commands.
public func runPrebuildCommands(for pluginResults: [PluginInvocationResult]) throws -> [PrebuildCommandResult] {
    // Run through all the commands from all the plugin usages in the target.
    return try pluginResults.map { pluginResult in
        // As we go we will collect a list of prebuild output directories whose contents should be input to the build,
        // and a list of the files in those directories after running the commands.
        var derivedSourceFiles: [AbsolutePath] = []
        var prebuildOutputDirs: [AbsolutePath] = []
        for command in pluginResult.prebuildCommands {
            // FIXME: Is it appropriate to emit this here?
            stdoutStream.write(command.configuration.displayName + "\n")
            stdoutStream.flush()
            
            // Run the command configuration as a subshell. This doesn't return until it is done.
            // TODO: We need to also use any working directory, but that support isn't yet available on all platforms at a lower level.
            // TODO: Invoke it in a sandbox that allows writing to only the temporary location.
            let commandLine = [command.configuration.executable] + command.configuration.arguments
            let processResult = try Process.popen(arguments: commandLine, environment: command.configuration.environment)
            let output = try processResult.utf8Output() + processResult.utf8stderrOutput()
            if processResult.exitStatus != .terminated(code: 0) {
                throw StringError("failed: \(command)\n\n\(output)")
            }

            // Add any files found in the output directory declared for the prebuild command after the command ends.
            let outputFilesDir = command.outputFilesDirectory
            if let swiftFiles = try? localFileSystem.getDirectoryContents(outputFilesDir).sorted() {
                derivedSourceFiles.append(contentsOf: swiftFiles.map{ outputFilesDir.appending(component: $0) })
            }
            
            // Add the output directory to the list of directories whose structure should affect the build plan.
            prebuildOutputDirs.append(outputFilesDir)
        }
        
        // Add the results of running any prebuild commands for this invocation.
        return PrebuildCommandResult(derivedSourceFiles: derivedSourceFiles, outputDirectories: prebuildOutputDirs)
    }
}

