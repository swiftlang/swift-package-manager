/// The `Plugin` protocol defines the functionality common to all types of
/// plugins, and there is a specific protocol for each of the defined plugin
/// capabilities (only the `BuildToolPlugin` is presently defined, but the
/// intent to is allow additional capabilities in the future).
///
/// Each plugin defines a type that conforms to the protocol corresponding
/// to the capability it provides, and annotates that type with `@main`.
/// It then implements the corresponding methods, which will be called to
/// perform the functionality of the plugin.

/// Defines functionality common to all plugins.
public protocol Plugin {
    /// Instantiates the plugin. This happens once per invocation of the
    /// plugin; there is no facility for keeping in-memory state from one
    /// invocation to the next. Most plugins do not need to implement the
    /// initializer.
    ///
    /// If a future version of SwiftPM allows the usage of a plugin to
    /// also provide configuration parameters for that plugin, then a new
    /// initializer that accepts that configuration could be added here.
    init()
}

/// Defines functionality for all plugins having a `buildTool` capability.
public protocol BuildToolPlugin: Plugin {
    /// Invoked by SwiftPM to create build commands for a particular target.
    /// The context parameter contains information about the package and its
    /// dependencies, as well as other environmental inputs.
    ///
    /// This function should create and return build commands or prebuild
    /// commands, configured based on the information in the context.
    func createBuildCommands(
        context: TargetBuildContext
    ) throws -> [Command]
}
