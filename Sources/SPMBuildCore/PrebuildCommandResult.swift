import Basics
import TSCBasic


/// Represents the result of running prebuild commands for a single plugin invocation for a target.
public struct PrebuildCommandResult {
    /// Paths of any derived source files that should be included in the build.
    public var derivedSourceFiles: [AbsolutePath]
    
    /// Paths of any directories whose contents influence the build plan.
    public var outputDirectories: [AbsolutePath]
}

/// Private function that runs a single prebuild command. Returns any output emitted by the command, as well as the paths of derived source files that should be passed into the build planning step. Throws an error if the command exits with a result code. The derived source directory paths is the list of directories whose contents should be included as generated sources.
private func runPrebuildCommand(_ executable: AbsolutePath, arguments: [String], environment: [String: String], workingDirectory: AbsolutePath?) throws -> ProcessResult {
    // TODO: We need to also respect any environment and working directory configurations.
    
    // Form the command line, and invoke the command.
    // TODO: Invoke it in a sandbox that allows writing to only the temporary location.
    let command = [executable.pathString] + arguments
    return try Process.popen(arguments: command)
}

/// Run any prebuild commands associated with the given list of prebuild results, in order, and returns the results.
public func runPrebuildCommands(for pluginResults: [PluginInvocationResult]) throws -> [PrebuildCommandResult] {
    // Run through all the commands from all the plugin usages in the target.
    var commandResults: [PrebuildCommandResult] = []
    for pluginResult in pluginResults {
        for command in pluginResult.commands {
            // We only run the prebuild commands here.
            guard case .prebuildCommand(let displayName, let executable, let arguments, let environment, let workingDir) = command else {
                continue
            }
            // FIXME: Is it appropriate to emit this here?
            stdoutStream.write(displayName + "\n")
            stdoutStream.flush()
            
            // Form the command line, and invoke the command.
            // TODO: We need to also respect any environment and working directory configurations.
            // TODO: Invoke it in a sandbox that allows writing to only the temporary location.
            let processResult = try runPrebuildCommand(AbsolutePath(executable), arguments: arguments, environment: environment, workingDirectory: workingDir)
            let output = try processResult.utf8Output() + processResult.utf8stderrOutput()
            if processResult.exitStatus != .terminated(code: 0) {
                throw StringError("failed: \(command)\n\n\(output)")
            }
        }
        
        // Add the source files from any directories declared as output directories.
        var derivedSourceFiles: [AbsolutePath] = []
        for dir in pluginResult.prebuildOutputDirectories {
            if let swiftFiles = try? localFileSystem.getDirectoryContents(dir).sorted() {
                derivedSourceFiles.append(contentsOf: swiftFiles.map{ dir.appending(component: $0) })
            }
        }
        
        // Add a result for this invocation.
        commandResults.append(PrebuildCommandResult(derivedSourceFiles: derivedSourceFiles, outputDirectories: pluginResult.prebuildOutputDirectories))
    }
    return commandResults
}

