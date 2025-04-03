//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// A command to run during a build.
///
/// A `Command` represents all of the parameters of the build comment,
/// including the executable, command-line arguments,
/// environment variables, initial working directory, and input and output files.
///
/// The system interprets relative paths starting from the path passed to the plugin in the target build context.
public enum Command {
    /// Returns a command that the system runs when a build needs updated versions of any of its output files.
    ///
    /// An output file is out-of-date if it doesn't exist, or if any input files
    /// are newer than the output file.
    ///
    /// - Note: The paths in the list of output files can depend on the paths in the list of input files,
    ///   but not on the content of input files. To create a command that generates output files based
    ///   on the content of its input files, use ``prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-enum.case``.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the command's executable.
    ///   - arguments: Command-line arguments the system passes to the executable.
    ///   - environment: Environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: Files on which the contents of output files may depend.
    ///     You should pass any paths you pass in `arguments` as input files.
    ///   - outputFiles: Files the build command generates or updates.
    ///     Any files the system recognizes by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     is generated as if they are in the target's source directory; the system
    ///     treats other files as resources as if they are explicitly listed in
    ///     `Package.swift` using
    ///     `.process(...)`.
    @available(_PackageDescription, introduced: 6.0)
    case buildCommand(
        displayName: String?,
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        inputFiles: [URL] = [],
        outputFiles: [URL] = []
    )

    /// Returns a command that the build system runs unconditionally before every build.
    ///
    /// Prebuild commands can have a significant performance impact,
    /// use them only when there's no way to know the
    /// list of output file paths without first reading the contents
    /// of one or more input files.
    ///
    /// Use the `outputFilesDirectory` parameter to tell the build system where the
    /// command creates or updates output files. The system treats all files in that
    /// directory after the command runs as output files.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the command's executable.
    ///   - arguments: Command-line arguments the system passes to the executable.
    ///   - environment: Environment variable assignments visible to the executable.
    ///   - outputFilesDirectory: A directory into which the command writes its
    ///     output files.  Any files in that directory that the system recognizes by their
    ///     extension as source files (for example, `.swift`) are compiled into the target
    ///     for which the system generated this command, as if they are in its source
    ///     directory; the system treats other files as resources as if explicitly listed in
    ///     `Package.swift` using `.process(...)`.
    @available(_PackageDescription, introduced: 6.0)
    case prebuildCommand(
        displayName: String?,
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        outputFilesDirectory: URL
    )
}

extension Command {
    /// Returns a command that the system runs when the build needs updated versions of any of its output files.
    ///
    /// An output file is out of date if it doesn't exist, or if any input files
    /// are newer than the output file.
    ///
    /// - Note: The paths in the list of output files can depend on the paths in the list of input files,
    ///   but not on the content of input files. To create a command that generates output files based
    ///   on the content of its input files, use ``prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-enum.case``.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the command's executable.
    ///   - arguments: Command-line arguments the system passes to the executable.
    ///   - environment: Environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: Files on which the contents of output files may depend.
    ///     You should pass any paths you pass in `arguments` as input files.
    ///   - outputFiles: Files the build command generates or updates.
    ///     Any files the system recognizes by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     is generated as if they are in the target's source directory; the system
    ///     treats other files as resources as if they are explicitly listed in
    ///     `Package.swift` using
    ///     `.process(...)`.
    @available(_PackageDescription, deprecated: 6.0, message: "Use `URL` type instead of `Path`.")
    public static func buildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) -> Command {
        self.buildCommand(
            displayName: displayName,
            executable: URL(fileURLWithPath: executable.stringValue),
            arguments: arguments.map(\.description),
            environment: environment.mapValues { $0.description },
            inputFiles: inputFiles.map { URL(fileURLWithPath: $0.stringValue) },
            outputFiles: outputFiles.map { URL(fileURLWithPath: $0.stringValue) }
        )
    }

    /// Returns a command that the system runs when the build needs updated versions of any of its output files.
    ///
    /// An output file is out of date if it doesn't exist, or if any input files
    /// are newer than the output file.
    ///
    /// - Note: The paths in the list of output files can depend on the paths in the list of input files,
    ///   but not on the content of input files. To create a command that generates output files based
    ///   on the content of its input files, use ``prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-enum.case``.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the command's executable.
    ///   - arguments: Command-line arguments the system passes to the executable.
    ///   - environment: Environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: Files on which the contents of output files may depend.
    ///     You should pass any paths you pass in `arguments` as input files.
    ///   - outputFiles: Files the build command generates or updates.
    ///     Any files the system recognizes by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     is generated as if they are in the target's source directory; the system
    ///     treats other files as resources as if they are explicitly listed in
    ///     `Package.swift` using
    ///     `.process(...)`.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    public static func buildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        workingDirectory: Path? = .none,
        inputFiles: [Path] = [],
        outputFiles: [Path] = []
    ) -> Command {
        self.buildCommand(
            displayName: displayName,
            executable: URL(fileURLWithPath: executable.stringValue),
            arguments: arguments.map(\.description),
            environment: environment.mapValues { $0.description },
            inputFiles: inputFiles.map { URL(fileURLWithPath: $0.stringValue) },
            outputFiles: outputFiles.map { URL(fileURLWithPath: $0.stringValue) }
        )
    }

    /// Returns a command that the build system runs unconditionally before every build.
    ///
    /// Prebuild commands can have a significant performance impact,
    /// use them only when there's no way to know the
    /// list of output file paths without first reading the contents
    /// of one or more input files.
    ///
    /// Use the `outputFilesDirectory` parameter to tell the build system where the
    /// command creates or updates output files. The system treats all files in that
    /// directory after the command runs as output files.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the command's executable.
    ///   - arguments: Command-line arguments the system passes to the executable.
    ///   - environment: Environment variable assignments visible to the executable.
    ///   - outputFilesDirectory: A directory into which the command writes its
    ///     output files.  Any files in that directory that the system recognizes by their
    ///     extension as source files (for example, `.swift`) are compiled into the target
    ///     for which the system generated this command, as if they are in its source
    ///     directory; the system treats other files as resources as if explicitly listed in
    ///     `Package.swift` using `.process(...)`.
    @available(_PackageDescription, deprecated: 6.0, message: "Use `URL` type instead of `Path`.")
    public static func prebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        outputFilesDirectory: Path
    ) -> Command {
        self.prebuildCommand(
            displayName: displayName,
            executable: URL(fileURLWithPath: executable.stringValue),
            arguments: arguments.map(\.description),
            environment: environment.mapValues { $0.description },
            outputFilesDirectory: URL(fileURLWithPath: outputFilesDirectory.stringValue)
        )
    }

    /// Returns a command that the build system runs unconditionally before every build.
    ///
    /// Prebuild commands can have a significant performance impact,
    /// use them only when there's no way to know the
    /// list of output file paths without first reading the contents
    /// of one or more input files.
    ///
    /// Use the `outputFilesDirectory` parameter to tell the build system where the
    /// command creates or updates output files. The system treats all files in that
    /// directory after the command runs as output files.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the command's executable.
    ///   - arguments: Command-line arguments the system passes to the executable.
    ///   - environment: Environment variable assignments visible to the executable.
    ///   - outputFilesDirectory: A directory into which the command writes its
    ///     output files.  Any files in that directory that the system recognizes by their
    ///     extension as source files (for example, `.swift`) are compiled into the target
    ///     for which the system generated this command, as if they are in its source
    ///     directory; the system treats other files as resources as if explicitly listed in
    ///     `Package.swift` using `.process(...)`.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not yet supported")
    public static func prebuildCommand(
        displayName: String?,
        executable: Path,
        arguments: [CustomStringConvertible],
        environment: [String: CustomStringConvertible] = [:],
        workingDirectory: Path? = .none,
        outputFilesDirectory: Path
    ) -> Command {
        self.prebuildCommand(
            displayName: displayName,
            executable: URL(fileURLWithPath: executable.stringValue),
            arguments: arguments.map(\.description),
            environment: environment.mapValues { $0.description },
            outputFilesDirectory: URL(fileURLWithPath: outputFilesDirectory.stringValue)
        )
    }
}
