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

/// A command to run during the build, including executable, command lines,
/// environment variables, initial working directory, etc. All paths should
/// be based on the ones passed to the plugin in the target build context.
public enum Command {
    
    case _buildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: Path? = nil,
        inputFiles: [Path] = [],
        outputFiles: [Path] = [])
    
    case _prebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: Path? = nil,
        outputFilesDirectory: Path)
}

public extension Command {
    
    /// Returns a command that runs when its ouputs are needed but out-of-date.  
    ///
    /// The command will run whenever its outputs are missing or if its
    /// inputs have changed since its outputs were created.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to be invoked.
    ///   - arguments: Command-line arguments to be passed to the executable.
    ///   - environment: Environment variable assignments visible to the executable.
    ///   - inputFiles: Files on which the contents of output files may depend.  
    ///     Any paths passed as `arguments` should typically be passed here as well.
    ///   - outputFiles: Files to be generated or updated by the executable.  Any
    ///     swift files are compiled into the target for which this command was 
    ///     generated; other files are treated as its resources as if by `.process(...)`.
    static func buildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) -> Command {
        return _buildCommand(
            displayName: displayName,
            executable: executable,
            arguments: arguments.map{ $0.description },
            environment: environment.mapValues{ $0.description },
            workingDirectory: .none,
            inputFiles: inputFiles,
            outputFiles: outputFiles)
    }

    /// Returns a command that runs when its ouputs are needed but out-of-date.  
    ///
    /// The command will run whenever its outputs are missing or if its
    /// inputs have changed since its outputs were created.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to be invoked.
    ///   - arguments: Command-line arguments to be passed to the executable.
    ///   - environment: Environment variable assignments visible to the executable.
    ///   - workingDirectory: Optional initial working directory when the executable
    ///     runs.
    ///   - inputFiles: Files on which the contents of output files may depend.  
    ///     Any paths passed as `arguments` should typically be passed here as well.
    ///   - outputFiles: Files to be generated or updated by the executable.  Any
    ///     swift files are compiled into the target for which this command was 
    ///     generated; other files are treated as its resources as if by `.process(...)`.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    static func buildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        workingDirectory: Path? = .none,
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) -> Command {
        return _buildCommand(
            displayName: displayName,
            executable: executable,
            arguments: arguments.map{ $0.description },
            environment: environment.mapValues{ $0.description },
            workingDirectory: workingDirectory,
            inputFiles: inputFiles,
            outputFiles: outputFiles)
    }

    /// Creates a command to run before the build. The executable should be a
    /// tool returned by `PluginContext.tool(named:)`, and any paths in the
    /// arguments list and in the output files directory should be based on
    /// the paths provided in the target build context structure.
    ///
    /// The build command will run before the build starts, and is allowed to
    /// create an arbitrary set of output files based on the contents of the
    /// inputs.
    ///
    /// Because prebuild commands are run on every build, they can have a
    /// significant performance impact and should only be used when there is
    /// no way to know the names of the outputs before the command is run.
    ///
    /// The `outputFilesDirectory` parameter is the path of a directory into
    /// which the command will write its output files. Any files that are in
    /// that directory after the prebuild command finishes will be interpreted
    /// according to the same build rules as for sources.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The executable to be invoked; should be a tool looked
    ///     up using `tool(named:)`, which may reference either a tool provided
    ///     by a binary target or build from source.
    ///   - arguments: Arguments to be passed to the tool. Any paths should be
    ///     based on the paths provided in the target build context.
    ///   - environment: Any custom environment assignments for the subprocess.
    ///   - outputFilesDirectory: A directory into which the command can write
    ///     output files that should be processed further.
    static func prebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        outputFilesDirectory: Path
    ) -> Command {
       return _prebuildCommand(
           displayName: displayName,
           executable: executable,
           arguments: arguments.map{ $0.description },
           environment: environment.mapValues{ $0.description },
           workingDirectory: .none,
           outputFilesDirectory: outputFilesDirectory)
    }

    /// Creates a command to run before the build. The executable should be a
    /// tool returned by `PluginContext.tool(named:)`, and any paths in the
    /// arguments list and in the output files directory should be based on
    /// the paths provided in the target build context structure.
    ///
    /// The build command will run before the build starts, and is allowed to
    /// create an arbitrary set of output files based on the contents of the
    /// inputs.
    ///
    /// Because prebuild commands are run on every build, they can have a
    /// significant performance impact and should only be used when there is
    /// no way to know the names of the outputs before the command is run.
    ///
    /// The `outputFilesDirectory` parameter is the path of a directory into
    /// which the command will write its output files. Any files that are in
    /// that directory after the prebuild command finishes will be interpreted
    /// according to the same build rules as for sources.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The executable to be invoked; should be a tool looked
    ///     up using `tool(named:)`, which may reference either a tool provided
    ///     by a binary target or build from source.
    ///   - arguments: Arguments to be passed to the tool. Any paths should be
    ///     based on the paths provided in the target build context.
    ///   - environment: Any custom environment assignments for the subprocess.
    ///   - workingDirectory: Optional initial working directory of the command.
    ///   - outputFilesDirectory: A directory into which the command can write
    ///     output files that should be processed further.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    static func prebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        workingDirectory: Path? = .none,
        outputFilesDirectory: Path
    ) -> Command {
        return _prebuildCommand(
            displayName: displayName,
            executable: executable,
            arguments: arguments.map{ $0.description },
            environment: environment.mapValues{ $0.description },
            workingDirectory: workingDirectory,
            outputFilesDirectory: outputFilesDirectory)
    }
}
