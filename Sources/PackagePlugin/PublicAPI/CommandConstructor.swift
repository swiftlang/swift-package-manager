/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// Constructs commands to run during the build, including command lines,
/// environment variables, initial working directory, etc. All paths should
/// be based on the ones passed to the plugin in the target build context.
public final class CommandConstructor {
    
    /// Prevents the CommandConstructor from being instantiated by the script.
    internal init() {}

    /// Creates a command to run during the build. The executable should be a
    /// tool returned by `TargetBuildContext.tool(named:)`, and any paths in
    /// the arguments list as well as in the input and output lists should be
    /// based on the paths provided in the target build context structure.
    ///
    /// The build command will run whenever its outputs are missing or if its
    /// inputs have changed since the command was last run. In other words,
    /// it is incorporated into the build command graph.
    ///
    /// This is the preferred kind of command to create when the outputs that
    /// will be generated are known ahead of time.
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
    ///   - inputFiles: Input files to the build command. Any changes to the
    ///     input files cause the command to be rerun.
    ///   - outputFiles: Output files that should be processed further according
    ///     to the rules defined by the build system.
    public func addBuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String] = [:],
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) {
        output.buildCommands.append(BuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: nil, inputFiles: inputFiles, outputFiles: outputFiles))
    }

    /// Creates a command to run during the build. The executable should be a
    /// tool returned by `TargetBuildContext.tool(named:)`, and any paths in
    /// the arguments list as well as in the input and output lists should be
    /// based on the paths provided in the target build context structure.
    ///
    /// The build command will run whenever its outputs are missing or if its
    /// inputs have changed since the command was last run. In other words,
    /// it is incorporated into the build command graph.
    ///
    /// This is the preferred kind of command to create when the outputs that
    /// will be generated are known ahead of time.
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
    ///   - inputFiles: Input files to the build command. Any changes to the
    ///     input files cause the command to be rerun.
    ///   - outputFiles: Output files that should be processed further according
    ///     to the rules defined by the build system.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    public func addBuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: Path? = nil,
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) {
        output.buildCommands.append(BuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory, inputFiles: inputFiles, outputFiles: outputFiles))
    }

    /// Creates a command to run before the build. The executable should be a
    /// tool returned by `TargetBuildContext.tool(named:)`, and any paths in
    /// the arguments list and the output files directory should be based on
    /// the paths provided in the target build context structure.
    ///
    /// The build command will run before the build starts, and is allowed to
    /// create an arbitrary set of output files based on the contents of the
    /// inputs.
    ///
    /// Because prebuild commands are run on every build, they are can have
    /// significant performance impact and should only be used when there is
    /// no way to know the names of the outputs before the command is run.
    ///
    /// The `outputFilesDirectory` parameter is the path of a directory into
    /// which the command will write its output files. Any files that are in
    /// that directory after the prebuild command finishes will be interpreted
    /// according to same build rules as for sources.
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
    public func addPrebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String] = [:],
        outputFilesDirectory: Path
    ) {
        output.prebuildCommands.append(PrebuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: nil, outputFilesDirectory: outputFilesDirectory))
    }

    /// Creates a command to run before the build. The executable should be a
    /// tool returned by `TargetBuildContext.tool(named:)`, and any paths in
    /// the arguments list and the output files directory should be based on
    /// the paths provided in the target build context structure.
    ///
    /// The build command will run before the build starts, and is allowed to
    /// create an arbitrary set of output files based on the contents of the
    /// inputs.
    ///
    /// Because prebuild commands are run on every build, they are can have
    /// significant performance impact and should only be used when there is
    /// no way to know the names of the outputs before the command is run.
    ///
    /// The `outputFilesDirectory` parameter is the path of a directory into
    /// which the command will write its output files. Any files that are in
    /// that directory after the prebuild command finishes will be interpreted
    /// according to same build rules as for sources.
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
    public func createPrebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: Path? = nil,
        outputFilesDirectory: Path
    ) {
        output.prebuildCommands.append(PrebuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory, outputFilesDirectory: outputFilesDirectory))
    }
}
