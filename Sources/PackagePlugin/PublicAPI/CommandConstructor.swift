/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// Constructs commands to run during the build, including full command lines.
/// All paths should be based on the ones passed to the plugin in the target
/// build context.
public final class CommandConstructor {
    /// Prevents the CommandConstructor from being instantiated by the script.
    internal init() {}

    /// Creates a command to run during the build. The executable should be a
    /// path returned by `TargetBuildContext.tool(named:)`, the inputs should
    /// be the files that are used by the command, and the outputs should be
    /// the files that are produced by the command.
    public func createBuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String]? = nil,
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) {
        output.buildCommands.append(BuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: nil, inputFiles: inputFiles, outputFiles: outputFiles))
    }

    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    public func createBuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: Path? = nil,
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) {
        output.buildCommands.append(BuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory, inputFiles: inputFiles, outputFiles: outputFiles))
    }

    /// Creates a command to run before the build. The executable should be a
    /// path returned by `TargetBuildContext.tool(named:)`, the output direc-
    /// tory should be a directory in which the command will create the output
    /// files that should be subject to further processing.
    public func createPrebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String]? = nil,
        outputFilesDirectory: Path
    ) {
        output.prebuildCommands.append(PrebuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: nil, outputFilesDirectory: outputFilesDirectory))
    }

    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    public func createPrebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: Path? = nil,
        outputFilesDirectory: Path
    ) {
        output.prebuildCommands.append(PrebuildCommand(displayName: displayName, executable: executable, arguments: arguments, environment: environment, workingDirectory: workingDirectory, outputFilesDirectory: outputFilesDirectory))
    }
}
