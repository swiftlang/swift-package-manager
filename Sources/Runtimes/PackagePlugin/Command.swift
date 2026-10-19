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
import PackageShared

public typealias Platform = PackageShared.Platform

public enum CommandArgument: ExpressibleByStringLiteral {
    case literal(String)
    case configuration
    case triple
    case sdkroot
    case sysroot
    case clangResourceDirectory
    case swiftResourceDirectory
    case buildSubDirectory

    public init(stringLiteral value: StringLiteralType) {
        self = .literal(value)
    }
}

extension CommandArgument: CustomStringConvertible {
    public var description: String {
        return switch self {
        case .literal(let value):
            value
        case .configuration:
            "$(CONFIGURATION)"
        case .triple:
            "$(TRIPLE)"
        case .sdkroot:
            "$(SDKROOT)"
        case .sysroot:
            "$(SYSROOT)"
        case .clangResourceDirectory:
            "$(CLANG_RESOURCE_DIR)"
        case .swiftResourceDirectory:
            "$(SWIFT_RESOURCE_DIR)"
        case .buildSubDirectory:
            "$(BUILD_SUBDIR)"
        }
    }
}

public extension Path {
    // These are absolute paths when resolved
    static var sdkroot: Self { .init(CommandArgument.sdkroot.description) }
    static var sysroot: Self { .init(CommandArgument.sysroot.description) }
    static var clangResourceDirectory: Self { .init(CommandArgument.clangResourceDirectory.description) }
    static var swiftResourceDirectory: Self { .init(CommandArgument.swiftResourceDirectory.description) }
}

public struct CommandConditions {
    public var platforms: [Platform]?
    public var traits: Set<String>?
}

extension CommandConditions {
    public static func when(platforms: [Platform], traits: Set<String>? = nil) -> Self {
        .init(platforms: platforms, traits: traits)
    }

    public static func when(traits: Set<String>? = nil) -> Self {
        .init(platforms: nil, traits: traits)
    }
}

/// A build product produced by a Command to be shared with downstream Commands.
public struct BuildProduct {
    /// The output file to be added as a build product
    public var outputFile: URL

    /// An optional subdirectory in the products directory this file will be copied to.
    public var productSubdir: String?

    /// Optionally, conditions on which this build product is produced.
    public var conditions: CommandConditions?

    public init(_ outputFile: URL, productSubdir: String? = nil, _ conditions: CommandConditions? = nil) {
        self.outputFile = outputFile
        self.productSubdir = productSubdir
        self.conditions = conditions
    }
}

/// A command to run during the build.
///
/// A command includes the executable, command lines, environment variables, initial working directory, and so on.
/// All paths should be based on the ones that SwiftPM passes to the plugin in the target build context.
public enum Command {
    /// Returns a command that runs when any of its output files are needed by
    /// the build and are out-of-date.
    ///
    /// An output file is out-of-date if it doesn't exist, or if any input files
    /// have changed since the command was last run.
    ///
    /// - Note: the paths in the list of output files may depend on the list of
    ///   input file paths, but **must not** depend on reading the contents of
    ///   any input files. Use a `prebuildCommand`if the functionality of your plugin
    ///   requires you to read the contents of an input file.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: A list of files on which the contents of output files may depend.
    ///     Any paths passed as `arguments` should typically be passed here as
    ///     well.
    ///   - outputFiles: A list of files to be generated or updated by the executable.
    ///     Any files recognizable by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     was generated as if in its source directory; other files are treated
    ///     as resources as if explicitly listed in `Package.swift` using
    ///     `.process(...)`.
    ///   - buildProducts: A list of files that serve as build products to be shared
    ///     with downstream commands.
    ///   - alwaysOutOfDate: When the command has no output files, whether to run
    ///     the command on all builds when set to true, or just once when set to false.
    ///   - conditions: Which platforms the command supports.
    @available(_PackageDescription, introduced: 6.5)
    case buildCommand(
        displayName: String?,
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        inputFiles: [URL] = [],
        outputFiles: [URL] = [],
        buildProducts: [BuildProduct] = [],
        alwaysOutOfDate: Bool = false,
        conditions: CommandConditions?
    )

    /// Returns a command that runs unconditionally before every build.
    ///
    /// Prebuild commands can have a significant performance impact
    /// and should only be used when there would be no way to know the
    /// list of output file paths without first reading the contents
    /// of one or more input files. Typically there is no way to
    /// determine this list without first running the command, so
    /// instead of encoding that list, the caller supplies an
    /// `outputFilesDirectory` parameter, and all files in that
    /// directory after the command runs are treated as the output files
    /// of the plugin.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the executable.
    ///   - outputFilesDirectory: A directory into which the command writes its
    ///     output files.  The package manager compiles any files there recognizable by
    ///     their extension as source files (for example, `.swift`) into the target for which
    ///     this command was generated as if in its source directory; other
    ///     files are treated as resources as if explicitly listed in
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
    /// Returns a command that runs when any of its output files are needed by
    /// the build and are out-of-date.
    ///
    /// An output file is out-of-date if it doesn't exist, or if any input files
    /// have changed since the command was last run.
    ///
    /// - Note: the paths in the list of output files may depend on the list of
    ///   input file paths, but **must not** depend on reading the contents of
    ///   any input files. Use a `prebuildCommand`if the functionality of your plugin
    ///   requires you to read the contents of an input file.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: A list of files on which the contents of output files may depend.
    ///     Any paths passed as `arguments` should typically be passed here as
    ///     well.
    ///   - outputFiles: A list of files to be generated or updated by the executable.
    ///     Any files recognizable by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     was generated as if in its source directory; other files are treated
    ///     as resources as if explicitly listed in `Package.swift` using
    ///     `.process(...)`.
    ///   - buildProducts: A list of files that serve as build products to be shared
    ///     with downstream commands.
    ///   - alwaysOutOfDate: When the command has no output files, whether to run
    ///     the command on all builds when set to true, or just once when set to false.
    ///   - conditions: Which platforms the command supports.
    @available(_PackageDescription, introduced: 6.5)
    public static func buildCommand(
        displayName: String?,
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        inputFiles: [URL] = [],
        outputFiles: [URL] = [],
        buildProducts: [BuildProduct] = [],
        alwaysOutOfDate: Bool = false,
        _ conditions: CommandConditions? = nil
    ) -> Self {
        .buildCommand(
            displayName: displayName,
            executable: executable,
            arguments: arguments,
            environment: environment,
            inputFiles: inputFiles,
            outputFiles: outputFiles,
            buildProducts: buildProducts,
            alwaysOutOfDate: alwaysOutOfDate,
            conditions: conditions
        )
    }

    /// Returns a command that runs when any of its output files are needed by
    /// the build and are out-of-date.
    ///
    /// An output file is out-of-date if it doesn't exist, or if any input files
    /// have changed since the command was last run.
    ///
    /// - Note: the paths in the list of output files may depend on the list of
    ///   input file paths, but **must not** depend on reading the contents of
    ///   any input files. Use a `prebuildCommand`if the functionality of your plugin
    ///   requires you to read the contents of an input file.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: A list of files on which the contents of output files may depend.
    ///     Any paths passed as `arguments` should typically be passed here as
    ///     well.
    ///   - outputFiles: A list of files to be generated or updated by the executable.
    ///     Any files recognizable by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     was generated as if in its source directory; other files are treated
    ///     as resources as if explicitly listed in `Package.swift` using
    ///     `.process(...)`.
    ///   - buildProducts: A list of files that serve as build products to be shared
    ///     with downstream commands.
    ///   - alwaysOutOfDate: When the command has no output files, whether to run
    ///     the command on all builds when set to true, or just once when set to false.
    ///   - platforms: An optional list of platforms that this build product will be produced for.
    @available(_PackageDescription, introduced: 6.0, obsoleted: 6.5)
    public static func buildCommand(
        displayName: String?,
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        inputFiles: [URL] = [],
        outputFiles: [URL] = [],
    ) -> Command {
        self.buildCommand(
            displayName: displayName,
            executable: executable,
            arguments: arguments,
            environment: environment,
            inputFiles: inputFiles,
            outputFiles: outputFiles,
            buildProducts: [],
            alwaysOutOfDate: false,
            conditions: nil
        )
    }

    /// Returns a command that runs when any of its output files are needed by
    /// the build and are out-of-date.
    ///
    /// An output file is out-of-date if it doesn't exist, or if any input files
    /// have changed since the command was last run.
    ///
    /// - Note: the paths in the list of output files may depend on the list of
    ///   input file paths, but **must not** depend on reading the contents of
    ///   any input files. Such cases must be handled using a `prebuildCommand`.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: Command-line arguments for the executable.
    ///   - environment: Environment variable assignments visible to the
    ///     executable.
    ///   - inputFiles: Files on which the contents of output files may depend.
    ///     Any paths passed as `arguments` should typically be passed here as
    ///     well.
    ///   - outputFiles: The files that the plugin generates or updates using the executable.
    ///     The package manager compiles any files recognizable by their extension as source files
    ///     (e.g. `.swift`) into the target for which this command
    ///     was generated as if in its source directory; other files are treated
    ///     as resources as if explicitly listed in `Package.swift` using
    ///     `.process(...)`.
    ///
    /// @DeprecationSummary {
    ///    Use ``buildCommand(displayName:executable:arguments:environment:inputFiles:outputFiles:)-swift.enum.case`` instead.
    /// }
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
            outputFiles: outputFiles.map { URL(fileURLWithPath: $0.stringValue) },
        )
    }

    /// Returns a command that runs when any of its output files are needed
    /// by the build and are out-of-date.
    ///
    /// An output file is out-of-date if it doesn't exist, or if any input
    /// files have changed since the command was last run.
    ///
    /// - Note: the paths in the list of output files may depend on the list
    ///   of input file paths, but **must not** depend on reading the contents
    ///   of any input files. Use a `prebuildCommand`if the functionality of your plugin
    ///   requires you to read the contents of an input file.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the executable.
    ///   - workingDirectory: Optional initial working directory when the executable
    ///     runs.
    ///   - inputFiles: A list of files on which the contents of output files may depend.
    ///     Any paths passed as `arguments` should typically be passed here as well.
    ///   - outputFiles: A list of files to be generated or updated by the executable.
    ///     Any files recognizable by their extension as source files
    ///     (for example, `.swift`) are compiled into the target for which this command
    ///     was generated as if in its source directory; other files are treated
    ///     as resources as if explicitly listed in `Package.swift` using
    ///     `.process(...)`.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not supported")
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
            outputFiles: outputFiles.map { URL(fileURLWithPath: $0.stringValue) },
            buildProducts: [],
            alwaysOutOfDate: false,
            conditions: nil
        )
    }

    /// Returns a command that runs unconditionally before every build.
    ///
    /// Prebuild commands can have a significant performance impact
    /// and should only be used when there would be no way to know the
    /// list of output file paths without first reading the contents
    /// of one or more input files. Typically there is no way to
    /// determine this list without first running the command, so
    /// instead of encoding that list, the caller supplies an
    /// `outputFilesDirectory` parameter, and all files in that
    /// directory after the command runs are treated as output files.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the executable.
    ///   - outputFilesDirectory: A directory into which the command writes its
    ///     output files.  Any files there recognizable by their extension as
    ///     source files (for example, `.swift`) are compiled into the target for which
    ///     this command was generated as if in its source directory; other
    ///     files are treated as resources as if explicitly listed in
    ///     `Package.swift` using `.process(...)`.
    /// @DeprecationSummary {
    ///   Use ``prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-swift.enum.case`` instead.
    /// }
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

    /// Returns a command that runs unconditionally before every build.
    ///
    /// Because prebuild commands are run on every build, they can have a
    /// significant performance impact and should only be used when there
    /// would be no way to know the list of output file paths without first
    /// reading the contents of one or more input files. Typically there is
    /// no way to determine this list without first running the command, so
    /// instead of encoding that list, the caller supplies an
    /// `outputFilesDirectory` parameter, and all files in that directory
    /// after the command runs are treated as output files.
    ///
    /// - parameters:
    ///   - displayName: An optional string to show in build logs and other
    ///     status areas.
    ///   - executable: The absolute path to the executable to invoke.
    ///   - arguments: The command-line arguments for the executable.
    ///   - environment: Any environment variable assignments visible to the executable.
    ///   - workingDirectory: Optional initial working directory when the executable
    ///     runs.
    ///   - outputFilesDirectory: A directory into which the command writes its
    ///     output files.  Any files there recognizable by their extension as
    ///     source files (for example, `.swift`) are compiled into the target for which
    ///     this command was generated as if in its source directory; other
    ///     files are treated as resources as if explicitly listed in
    ///     `Package.swift` using `.process(...)`.
    @available(*, unavailable, message: "specifying the initial working directory for a command is not supported")
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
