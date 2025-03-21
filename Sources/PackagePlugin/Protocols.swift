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

/// Defines functionality common to all SwiftPM plugins, such as the way to
/// instantiate the plugin.
///
/// A future improvement to SwiftPM would be to allow usage of a plugin to
/// also provide configuration parameters for that plugin. A proposal that
/// adds such a facility should also add initializers to set those values
/// as plugin properties.
public protocol Plugin {
    /// Instantiates the plugin. This happens once per invocation of the
    /// plugin; there is no facility for keeping in-memory state from one
    /// invocation to the next. Most plugins do not need to implement the
    /// initializer.
    init()
}

/// A protocol you implement to define a build-tool plugin.
public protocol BuildToolPlugin: Plugin {
    /// Creates build commands for the given target.
    ///
    /// - Parameters:
    ///   - context: Information about the package and its
    ///     dependencies, as well as other environmental inputs.
    ///   - target: The build target for which the package manager invokes the plugin.
    /// - Returns: A list of commands that the system runs before it performs the build action (for ``Command/prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-enum.case``),
    ///   or as specific steps during the build (for ``Command/buildCommand(displayName:executable:arguments:environment:inputFiles:outputFiles:)-enum.case``).
    ///
    /// You don't run commands directly in your implementation of this method. Instead, create and return ``Command`` instances.
    /// The system runs pre-build commands before it performs the build action, and adds build commands to the dependency tree for the build
    /// based on which steps create the command's inputs, and which steps depend on the command's outputs.
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command]
}

/// A protocol you implement to define a command plugin.
public protocol CommandPlugin: Plugin {
    /// Performs the command's custom actions.
    ///
    /// - Parameters:
    ///   - context: Information about the package and other environmental inputs.
    ///   - arguments: Literal arguments that someone passed in the command invocation, after the command verb.
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws

    /// An object that represents the Swift Package Manager or IDE hosting the command plugin.
    ///
    /// Use this object to discover specialized information about the plugin host, or actions your plugin can invoke.
    var packageManager: PackageManager { get }
}

extension CommandPlugin {    
    /// An object that represents the Swift Package Manager or IDE hosting the command plugin.
    public var packageManager: PackageManager {
        return PackageManager()
    }
}
