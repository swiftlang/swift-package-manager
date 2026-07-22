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

/// A collection of information about the package on which the package manager invokes the  plugin,
/// as well as contextual information based on the plugin's intent and requirements.
public struct PluginContext {
    /// Information about the package the plugin works on.
    public let package: Package

    /// The path of a writable directory into which the plugin or the build
    /// commands can write files.
    ///
    /// This could include
    /// generated source files to processed further, as well as
    /// any caches used by the build tool or the plugin.
    /// The plugin is in complete control of what is written under this directory,
    /// and the package manager preserves the contents between builds.
    ///
    /// A plugin may create a separate subdirectory
    /// for each command it creates, with the command configured to
    /// write its output to that directory. The plugin may also create other
    /// directories for cache files and other file system content that either
    /// it or the command will need.
    @available(_PackageDescription, deprecated: 6.0, renamed: "pluginWorkDirectoryURL")
    public let pluginWorkDirectory: Path

    /// The URL of a writable directory into which the plugin or the build
    /// commands it constructs can write anything it wants.
    ///
    /// This could include
    /// generated source files to processed further, as well as
    /// any caches used by the build tool or the plugin.
    /// The plugin is in complete control of what is written under this directory,
    /// and the package manager preserves the contents between builds.
    ///
    /// A plugin may create a separate subdirectory
    /// for each command it creates, with the command configured to
    /// write its output to that directory. The plugin may also create other
    /// directories for cache files and other file system content that either
    /// it or the command will need.
    @available(_PackageDescription, introduced: 6.0)
    public let pluginWorkDirectoryURL: URL

    /// Finds a command-line executable available to the plugin.
    ///
    /// The plugin host first looks for a matching tool provided by a direct
    /// dependency of the plugin target. Use the target name for an executable
    /// target dependency, the product name for an executable product dependency,
    /// or the executable artifact name from the artifact bundle metadata for a
    /// binary target dependency.
    ///
    /// If no declared dependency provides a matching tool, the plugin host may
    /// search additional directories. The directories and their order are
    /// specific to the host. Declare every required tool as a plugin dependency
    /// to make the plugin portable between SwiftPM, IDEs, and other hosts.
    ///
    /// Tool names are case sensitive.
    ///
    /// - Parameter name: The name of the executable to find.
    /// - Returns: Information about the matching host executable.
    /// - Throws: ``PluginContextError/toolNotSupportedOnTargetPlatform(name:)``
    ///   if a declared binary tool has no variant for the host platform, or
    ///   ``PluginContextError/toolNotFound(name:)`` if no matching tool is
    ///   available.
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

    /// A map of the tools provided by the plugin target's direct dependencies.
    ///
    /// This is not directly available to the plugin, but is used by ``tool(named:)``.
    let accessibleTools: [String: (path: URL, triples: [String]?)]

    /// Host-provided paths in which to search for tools that aren't in
    /// `accessibleTools`.
    @available(_PackageDescription, deprecated: 6.0, renamed: "toolSearchDirectoryURLs")
    let toolSearchDirectories: [Path]

    /// Host-provided URLs in which to search for tools that aren't in
    /// `accessibleTools`.
    @available(_PackageDescription, introduced: 6.0)
    let toolSearchDirectoryURLs: [URL]

    /// Information about a particular tool that is available to a plugin.
    public struct Tool {
        /// The name of the tool, suitable for display purposes.
        public let name: String

        /// The path of the tool in the file system.
        @available(_PackageDescription, deprecated: 6.0, renamed: "url")
        public var path: Path {
            get { _path }
        }

        /// The file URL of the tool in the file system.
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
