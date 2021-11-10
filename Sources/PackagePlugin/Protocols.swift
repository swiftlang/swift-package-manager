/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

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

/// Defines functionality for all plugins having a `buildTool` capability.
public protocol BuildToolPlugin: Plugin {
    /// Invoked by SwiftPM to create build commands for a particular target.
    /// The context parameter contains information about the package and its
    /// dependencies, as well as other environmental inputs.
    ///
    /// This function should create and return build commands or prebuild
    /// commands, configured based on the information in the context. Note
    /// that it does not directly run those commands.
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command]

    /// Invoked by SwiftPM to create build commands for a particular target.
    /// The context parameter contains information about the package and its
    /// dependencies, as well as other environmental inputs.
    ///
    /// This function should create and return build commands or prebuild
    /// commands, configured based on the information in the context.
    ///
    /// This is the old form of this method and is marginally deprecated.
    func createBuildCommands(
        context: TargetBuildContext
    ) throws -> [Command]
}

extension BuildToolPlugin {
    /// Default implementation that invokes the old callback with an old-style
    /// context, for compatibility.
    public func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        return try self.createBuildCommands(context: TargetBuildContext(
            targetName: target.name,
            moduleName: (target as? SourceModuleTarget)?.moduleName ?? target.name,
            targetDirectory: target.directory,
            packageDirectory: context.package.directory,
            inputFiles: (target as? SourceModuleTarget)?.sourceFiles ?? .init([]),
            dependencies: target.recursiveTargetDependencies.map { .init(
                targetName: $0.name,
                moduleName: ($0 as? SourceModuleTarget)?.moduleName ?? $0.name,
                targetDirectory: $0.directory,
                publicHeadersDirectory: ($0 as? ClangSourceModuleTarget)?.publicHeadersDirectory) },
            pluginWorkDirectory: context.pluginWorkDirectory,
            builtProductsDirectory: context.builtProductsDirectory,
            toolNamesToPaths: context.toolNamesToPaths))
    }

    /// Default implementation that does nothing.
    public func createBuildCommands(
        context: TargetBuildContext
    ) throws -> [Command] {
        return []
    }
}

