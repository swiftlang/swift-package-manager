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

    /// Looks up and returns the path of a named command line executable.
    /// 
    /// The executable must be provided by an executable target or binary
    /// target on which the package plugin target depends. This function throws
    /// an error if the tool cannot be found. The lookup is case sensitive.
    /// - Parameter name: The name of the executable to find.
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

    /// A map from tool names to their paths and triples.
    ///
    /// This is not directly available to the plugin, but is used by  ``tool(named:)``.
    let accessibleTools: [String: (path: URL, triples: [String]?)]

    /// The paths of directories in which to search for tools that aren't in
    /// the `toolNamesToPaths` map.
    @available(_PackageDescription, deprecated: 6.0, renamed: "toolSearchDirectoryURLs")
    let toolSearchDirectories: [Path]

    /// The paths of directories in which to search for tools that aren't in
    /// the `toolNamesToPaths` map.
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
