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

import Foundation

/// Provides information about the package for which the plugin is invoked.
///
/// The plugin context includes metadata about the package, and information about the
/// build environment in which the plugin runs.
public struct PluginContext {
    /// Information about the package to which the plugin is applied.
    public let package: Package

    /// The path to a directory into which the plugin or its build
    /// commands can write data.
    ///
    /// @DeprecationSummary{Use ``pluginWorkDirectoryURL`` instead.}
    ///
    /// The plugin and its build commands use the work directory to
    /// store any generated source files that the build system processes further,
    /// and for cache files that the plugin and its build commands use.
    /// The plugin is in complete control of what is written under this directory,
    /// and the system preserves its contents between builds.
    ///
    /// A common pattern is for a plugin to create a separate subdirectory of this
    /// directory for each build command it creates, and configure the build
    /// command to write its outputs to that subdirectory. The plugin may also
    /// create other directories for cache files and other file system content that either
    /// it or its build commands need.
    @available(_PackageDescription, deprecated: 6.0, renamed: "pluginWorkDirectoryURL")
    public let pluginWorkDirectory: Path

    /// The URL that locates a directory into which the plugin or its build
    /// commands can write data.
    ///
    /// @DeprecationSummary{Use ``pluginWorkDirectoryURL`` instead.}
    ///
    /// The plugin and its build commands use the work directory to
    /// store any generated source files that the build system processes further,
    /// and for cache files that the plugin and its build commands use.
    /// The plugin is in complete control of what is written under this directory,
    /// and the system preserves its contents between builds.
    ///
    /// A common pattern is for a plugin to create a separate subdirectory of this
    /// directory for each build command it creates, and configure the build
    /// command to write its outputs to that subdirectory. The plugin may also
    /// create other directories for cache files and other file system content that either
    /// it or its build commands need.
    @available(_PackageDescription, introduced: 6.0)
    public let pluginWorkDirectoryURL: URL

    /// Finds a named command-line tool.
    ///
    /// The tool's executable must be provided by an executable target or a binary
    /// target on which the package plugin target depends. This function throws
    /// an error if the system can't find the tool.
    ///
    /// - Parameter name: The case-sensitive name of the tool to find.
    /// - Returns An object that represents the command-line tool.
    public func tool(named name: String) throws -> Tool {
        if let tool = self.accessibleTools[name] {
            // For PluginAccessibleTool.builtTool, the triples value is not saved, thus
            // the value is always nil; this is intentional since if we are able to
            // build the tool, it is by definition supporting the target platform.
            // For PluginAccessibleTool.vendedTool, only supported triples are saved,
            // so empty triples means the tool is not supported on the target platform.
            if let triples = tool.triples, triples.isEmpty {
                throw PluginContextError.toolNotSupportedOnTargetPlatform(name: name)
            }
            return try Tool(name: name, path: Path(url: tool.path), url: tool.path)
        } else {
            for dir in self.toolSearchDirectoryURLs {
                #if os(Windows)
                let hostExecutableSuffix = ".exe"
                #else
                let hostExecutableSuffix = ""
                #endif
                let pathURL = dir.appendingPathComponent(name + hostExecutableSuffix)
                let path = try Path(url: pathURL)
                if FileManager.default.isExecutableFile(atPath: path.stringValue) {
                    return Tool(name: name, path: path, url: pathURL)
                }
            }
        }
        throw PluginContextError.toolNotFound(name: name)
    }

    /// A mapping from tool names to their paths and triples. Not directly available
    /// to the plugin, but used by the `tool(named:)` API.
    let accessibleTools: [String: (path: URL, triples: [String]?)]

    /// The paths of directories of in which to search for tools that aren't in
    /// the `toolNamesToPaths` map.
    @available(_PackageDescription, deprecated: 6.0, renamed: "toolSearchDirectoryURLs")
    let toolSearchDirectories: [Path]

    /// The paths of directories of in which to search for tools that aren't in
    /// the `toolNamesToPaths` map.
    @available(_PackageDescription, introduced: 6.0)
    let toolSearchDirectoryURLs: [URL]

    /// Information about a particular tool that is available to a plugin.
    public struct Tool {
        /// The tool's name.
        ///
        /// This property is suitable for display in a UI.
        public let name: String

        /// The full path to the tool in the file system.
        ///
        /// @DeprecationSummary{Use ``url`` instead.}
        @available(_PackageDescription, deprecated: 6.0, renamed: "url")
        public var path: Path {
            get { _path }
        }

        /// A URL that locates the tool in the file system.
        @available(_PackageDescription, introduced: 6.0)
        public let url: URL

        private let _path: Path

        @_spi(PackagePluginInternal) public init(name: String, path: Path, url: URL) {
            self.name = name
            self.url = url
            self._path = path
        }
    }
}
