# Writing a command plugin

@Metadata {
    @Available("Swift", introduced: "5.6")
}

Create a command plugin to provide commands that extend the package manager.

## Overview

The first step when writing a package plugin is to decide what kind of plugin you need.  

Implement a command plugin to provide actions that users can perform at any time and that are not associated with a build.

> Note: If your goal is to generate source files that should be part of a build, or to perform other actions at the start of every build, implement a build tool plugin.
> See <doc:WritingBuildToolPlugin> for details about creating a build tool plugin.

Command plugins are invoked at will by the user, by invoking `swift` `package` `<command>` `<arguments>`.
They are unrelated to the build graph, and often perform their work by invoking to command line tools as subprocesses.

Command plugins are declared in a similar way to build tool plugins, except that they declare a `.command()` capability and implement a different entry point in the plugin script.

A command plugin specifies the semantic intent of the command — this might be one of the predefined intents such as “documentation generation” or “source code formatting”, or it might be a custom intent with a specialized verb that can be passed to the `swift` `package` command.
A command plugin can also specify any special permissions it needs, such as the permission to modify the files under the package directory.

The command's intent declaration provides a way of grouping command plugins by their functional categories, so that package manager — or an IDE that supports package manager packages — can show the commands that are available for a particular purpose.
For example, this approach supports having different command plugins for generating documentation for a package, while still allowing those different commands to be grouped and discovered by intent.

A plugin is available to the package that defines it, and if there is a corresponding plugin product, it is also available to any other package that has a direct dependency on the package.

### Declaring a command plugin in the package manifest

The manifest of a package that declares a command plugin might look like:

```swift
import PackageDescription

let package = Package(
  name: "MyPluginPackage",
  products: [
    .plugin(
      name: "MyCommandPlugin",
      targets: [
        "MyCommandPlugin"
      ]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/example/sometool",
      from: "0.1.0"
    )
  ],
  targets: [
    .plugin(
      name: "MyCommandPlugin",
      capability: .command(
        intent: .sourceCodeFormatting(),
        permissions: [
          .writeToPackageDirectory(reason: "This command reformats source files")
        ]
      ),
      dependencies: [
        .product(name: "SomeTool", package: "sometool"),
      ]
    )
  ]
)
```

In the above example, the plugin declares its purpose is source code formatting, and that it needs permission to modify files in the package directory.
The package manager runs plugins in a sandbox that prevents network access and most file system access.
Package manager allows additional permissions to allow network access or file system acess when you declare them after it receives approval from the user.

### Implementing the command plugin script

The source that implements command plugins should be located under the `Plugins` subdirectory in the package.
Conform the entry point of the plugin to the `CommandPlugin` protocol:

```swift
import PackagePlugin
import Foundation

@main
struct MyCommandPlugin: CommandPlugin {
123456789012345678901234567890123456789012345678901234567890
  func performCommand(
    context: PluginContext,
    arguments: [String]
  ) throws {
    // To invoke `sometool` to format code, start by locating it.
    let sometool = try context.tool(named: "sometool")

    // By convention, use a configuration file in the root 
    // directory of the package. This allows package owners to 
    // commit their format settings to their repository.
    let configFile = context
      .package
      .directory
      .appending(".sometoolconfig")

    // Extract the target arguments (if there are none, assume all).
    var argExtractor = ArgumentExtractor(arguments)
    let targetNames = argExtractor.extractOption(named: "target")
    let targets = targetNames.isEmpty
      ? context.package.targets
      : try context.package.targets(named: targetNames)

    // Iterate over the provided targets to format.
    for target in targets {
      // Skip any type of target that doesn't have 
      // source files.
      // Note: This could instead emit a warning or error.
      guard let target = target.sourceModule else { continue }

      // Invoke `sometool` on the target directory, passing 
      // a configuration file from the package directory.
      let sometoolExec = URL(fileURLWithPath: sometool.path.string)
      let sometoolArgs = [
        "--config",
        "\(configFile)",
        "--cache", 
        "\(context.pluginWorkDirectory.appending("cache-dir"))",
        "\(target.directory)"
      ]
      let process = try Process.run(sometoolExec, 
                                    arguments: sometoolArgs)
      process.waitUntilExit()

      // Check whether the subprocess invocation was successful.
      if process.terminationReason == .exit 
        && process.terminationStatus == 0
      {
        print("Formatted the source code in \(target.directory).")
      } else {
        let problem = "\(process.terminationReason):\(process.terminationStatus)"
        Diagnostics.error("Formatting invocation failed: \(problem)")
      }
    }
  }
}
```

Unlike build tool plugins, which apply to a single package target, a command plugin does not necessarily operate on just a single target.
The `context` parameter provides access to the inputs, including to a distilled version of the package graph rooted at the package to which the command plugin is applied.

Command plugins can accept arguments, which you use to control options for the plugin's actions or further narrow down what the plugin operates on.
This example uses the convention of passing `--target` to limit the scope of the plugin to a set of targets in the package.

Plugins can only use standard system libraries, not those from other packages such as `SwiftArgumentParser`.
Consequently, the plugin example uses the built-in `ArgumentExtractor` helper in the *PackagePlugin* module to extract the argument.

### Diagnostics

Plugin entry points are marked `throws`, and any errors thrown from the entry point causes the plugin invocation to be marked as having failed.
The thrown error is presented to the user, and should include a clear description of what went wrong.

Additionally, plugins can use the `Diagnostics` API in PackagePlugin to emit warnings and errors that optionally include references to file paths and line numbers in those files.

### Debugging and Testing

Package manager doesn't currently have any specific support for debugging and testing plugins.
Many plugins act as adapters that construct command lines for invoking the tools that do the real work.
In the cases in which there is non-trivial code in a plugin, a good approach is to factor out that code into separate source files that can be included in unit tests using symbolic links with relative paths.

### Xcode Extensions to the PackagePlugin API

When you invoke a plugin in Apple’s Xcode IDE, the plugins has access to a library module provided by Xcode called *XcodeProjectPlugin*. 
This module extends the *PackagePlugin* APIs to let plugins work on Xcode targets in addition to packages.

In order to write a plugin that works with packages in every environment, and that conditionally works with Xcode projects when run in Xcode, the plugin should conditionally import the *XcodeProjectPlugin* module when it is available.
For example:

```swift
import PackagePlugin

@main
struct MyCommandPlugin: CommandPlugin {
    /// This entry point is called when operating on a Swift package.
    func performCommand(context: PluginContext,
                        arguments: [String]) throws {
        debugPrint(context)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension MyCommandPlugin: XcodeCommandPlugin {
    /// This entry point is called when operating on an Xcode project.
    func performCommand(context: XcodePluginContext, 
                        arguments: [String]) throws {
        debugPrint(context)
    }
}
#endif
```

The `XcodePluginContext` input structure is similar to the `PluginContext` structure, except that it provides access to an Xcode project. 
The Xcode project uses Xcode naming and semantics for the project model, which is somewhat different from that of package manager.
Some of the underlying types, such as `FileList`, or `Path`, are the same for `PackagePlugin` and `XcodeProjectPlugin`.

If any targets are chosen in the Xcode user interface, Xcode passes their names as `--target` arguments to the plugin.

Other IDEs or custom environments that use the package manager could similarly provide modules that define new entry points and extend the functionality of the core `PackagePlugin` APIs.
