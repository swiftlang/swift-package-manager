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

@_implementationOnly import Foundation

/// Provides information about the package for which the plugin is invoked,
/// as well as contextual information based on the plugin's stated intent
/// and requirements.
public struct PluginContext {
    /// Information about the package to which the plugin is being applied.
    public let package: Package

    /// The path of a writable directory into which the plugin or the build
    /// commands it constructs can write anything it wants. This could include
    /// any generated source files that should be processed further, and it
    /// could include any caches used by the build tool or the plugin itself.
    /// The plugin is in complete control of what is written under this di-
    /// rectory, and the contents are preserved between builds.
    ///
    /// A plugin would usually create a separate subdirectory of this directory
    /// for each command it creates, and the command would be configured to
    /// write its outputs to that directory. The plugin may also create other
    /// directories for cache files and other file system content that either
    /// it or the command will need.
    public let pluginWorkDirectory: Path

    /// Looks up and returns the path of a named command line executable tool.
    /// The executable must be provided by an executable target or a binary
    /// target on which the package plugin target depends. This function throws
    /// an error if the tool cannot be found. The lookup is case sensitive.
    public func tool(named name: String) throws -> Tool {
        if let path = self.toolNamesToPaths[name] {
            return Tool(name: name, path: path)
        } else {
            for dir in toolSearchDirectories {
#if os(Windows)
                let hostExecutableSuffix = ".exe"
#else
                let hostExecutableSuffix = ""
#endif
                let path = dir.appending(name + hostExecutableSuffix)
                if FileManager.default.isExecutableFile(atPath: path.string) {
                    return Tool(name: name, path: path)
                }
            }
        }
        throw PluginContextError.toolNotFound(name: name)
    }

    /// A mapping from tool names to their definitions. Not directly available
    /// to the plugin, but used by the `tool(named:)` API.
    let toolNamesToPaths: [String: Path]
    
    /// The paths of directories of in which to search for tools that aren't in
    /// the `toolNamesToPaths` map.
    let toolSearchDirectories: [Path]

    /// Information about a particular tool that is available to a plugin.
    public struct Tool {
        /// Name of the tool (suitable for display purposes).
        public let name: String

        /// Full path of the built or provided tool in the file system.
        public let path: Path
    }
}
