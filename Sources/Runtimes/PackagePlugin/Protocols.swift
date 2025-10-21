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

// A future improvement to the package manager would be to allow use of
// a plugin to also provide configuration parameters for that plugin.
// Any proposal that adds such a facility should also add initializers
// to set those values as plugin properties.

/// A protocol that defines functionality common to all package manger plugins.
///
/// For example, the way to instantiate and run a plugin.
public protocol Plugin {


    /// Instantiates the plugin.
    ///
    /// This happens once per invocation of the plugin.
    /// There is no facility for keeping in-memory state from one invocation to the next.
    /// Most plugins do not need to implement the initializer.
    init()
}

/// The plugin protocol that defines functionality for all plugins having a buildTool capability.
public protocol BuildToolPlugin: Plugin {
    /// Invoked by the package manager to create build commands for a particular target.
    ///
    /// The context parameter contains information about the package and its
    /// dependencies, as well as other environmental inputs.
    ///
    /// This function should create and return build commands or prebuild
    /// commands, configured based on the information in the context. Note
    /// that the plugin does not directly run those commands.
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command]
}

/// The plugin protocol that defines functionality for all plugins that have a command capability.
public protocol CommandPlugin: Plugin {
    /// Invoked by the package manager to perform the custom actions of the command.
    func performCommand(
        /// The context in which the plugin is invoked.
        ///
        /// This is the same for all kinds of plugins, and provides access to the package graph,
        /// to cache directories, and so on.
        context: PluginContext,
        
        /// Any literal arguments passed after the verb in the command invocation.
        arguments: [String]
    ) async throws

    /// A proxy to the Swift Package Manager or IDE hosting the command plugin,
    /// through which the plugin can ask for specialized information or actions.
    var packageManager: PackageManager { get }
}

extension CommandPlugin {    
    /// A proxy to the Swift Package Manager or IDE hosting the command plugin,
    /// through which the plugin can ask for specialized information or actions.
    public var packageManager: PackageManager {
        return PackageManager()
    }
}
