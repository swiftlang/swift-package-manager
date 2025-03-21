# ``PackagePlugin``

Create custom build steps and command-line actions for your Swift package.

## Overview

Use `PackagePlugin` to create plugins that extend Swift package manager's behavior in one of two ways:

* term Build-tool plugins: Create a command that Swift package manager runs either as a pre-build step before it performs a build action, or as a specific step in a target's build process.
* term Command plugins: Create a command that someone runs either by passing its name as an argument to the `swift package` command-line tool, or from UI their developer environment.

Define your plugins as targets in your `Package.swift` file.
To make a build-tool plugin available for other packages to use, define a product that exports the plugin.

### Create a build-tool plugin

Add a build-tool plugin target to your package by creating a `.plugin` target with the `buildTool()` capability in your package description.
List any command-line tools the plugin uses as dependencies of the plugin target, and their packages as dependencies of your package.
For example:

```swift
// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyPluginPackage",
    dependencies: [
        .package(
            url: "https://github.com/example/sometool",
            from: "0.1.0"
        )
    ],
    targets: [
        .plugin(
            name: "MyBuildToolPlugin",
            capability: .buildTool(),
            dependencies: [
                .product(name: "SomeTool", package: "sometool"),
            ]
        )
    ]
)

```

Create a `Plugins` folder in your Swift package, and a sub-folder with the same name as your build-tool plugin.
Inside that sub-folder, create a Swift file that contains your plugin source.
Your plugin needs to conform to ``BuildToolPlugin``.

Your implementation of ``BuildToolPlugin/createBuildCommands(context:target:)`` returns either a ``Command/buildCommand(displayName:executable:arguments:environment:inputFiles:outputFiles:)-enum.case`` or ``Command/prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-enum.case``, depending on where in the build process your plugin's command runs:

 - Return ``Command/buildCommand(displayName:executable:arguments:environment:inputFiles:outputFiles:)-enum.case`` if your plugin depends on one or more input files in the target's source (including files that the build process generates), and creates one or more output files that you know the paths to.
   Swift package manager adds your plugin's command to the dependency graph at a point where all of its inputs are available.
- Return ``Command/prebuildCommand(displayName:executable:arguments:environment:outputFilesDirectory:)-enum.case`` if your plugin creates a collection of output files with names that you don't know until after the command runs.
   Swift package manager runs your plugin's command every time it builds the target, before it calculates the target's dependency graph.

Use the ``PluginContext`` Swift package manager passes to your plugin to get information about the target Swift package manager is building, and to find the paths to commands your plugin uses.

### Use a build-tool plugin

In your target that uses a build-tool plugin as part of its build process, add the `plugins:` argument to the target's definition in your package description.
Each entry in the list is a `.plugin(name:package:)` that specifies the plugin's name, and the package that provides the plugin.
For example:

```swift
// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "my-plugin-using-example",
    dependencies: [
        .package(url: "https://github.com/example/my-plugin-package.git", from: "1.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyExample",
            plugins: [
                .plugin(name: "MyBuildToolPlugin", package: "my-plugin-package"),
            ]
        )
    ]
)
```

### Create a command plugin

Add a command plugin to your package by creating a `.plugin` target with the `command()` capability in your package description.
The capability describes the intent of your command plugin, and the permissions it needs to work.
List any commands your plugin uses as the target's dependencies.
For example:

```swift
// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyPluginPackage",
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
Create a `Plugins` folder in your Swift package, and a sub-folder with the same name as your build-tool plugin.
Inside that sub-folder, create a Swift file that contains your plugin source.
Your plugin needs to conform to ``CommandPlugin``.

Your implementation of ``CommandPlugin/performCommand(context:arguments:)`` runs the command and prints any output.
Use methods on ``Diagnostics`` to report errors, warnings, progress, and other information to the person who runs your command plugin.
Use ``ArgumentExtractor`` to parse arguments someone supplies to your command.

Use the ``PluginContext`` Swift package manager passes to your plugin to find paths to commands your plugin uses.
Command plugins don't have target information in their `PluginContext` structure, because Swift package manager isn't building a target when it runs your command plugin.

### Use a command plugin 

To run a command plugin, pass its name and any arguments it needs as arguments to the `swift package` command, for example:

```sh
% swift package my-plugin --example-flag parameter
```

### Share a plugin with other packages

Make your plugin available to developers to use in other packages by declaring a `.plugin` product in your package description, that has your plugin target in its targets list.
For example:

```swift
// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyPluginPackage",
    products: [
        .plugin(
            name: "MyBuildToolPlugin",
            targets: [
                "MyBuildToolPlugin"
            ]
        )
    ],
    // Define the plugin.
)
```

## Topics

### Build-tool plugins

- ``BuildToolPlugin``
- ``Command``
- ``Target``

### Command plugins

- ``CommandPlugin``
- ``ArgumentExtractor``

### Contextual information

- ``PluginContext``
- ``PackageManager``
- ``ToolsVersion``

### Packages

- ``Package``
- ``PackageOrigin``

### Package products

- ``Product``
- ``ExecutableProduct``
- ``LibraryProduct``

### Targets and modules

- ``BinaryArtifactTarget``
- ``SourceModuleTarget``
- ``ClangSourceModuleTarget``
- ``SwiftSourceModuleTarget``
- ``SystemLibraryTarget``
- ``ModuleKind``

### Files and paths

- ``FileList``
- ``File``
- ``FileType``
- ``PathList``
- ``Path``

### Dependencies

- ``PackageDependency``
- ``TargetDependency``

### Errors and feedback

- ``Diagnostics``
- ``PackageManagerProxyError``
- ``PluginContextError``
- ``PluginDeserializationError``

### Types that support plugins

- ``Plugin``
