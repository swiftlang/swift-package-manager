# Writing a build tool plugin

@Metadata {
    @Available("Swift", introduced: "5.6")
}

Create a build tool to process or generate files.

## Overview

The first step when writing a package plugin is to decide what kind of plugin you need.
Implement a build tool plugin to generate source files that should be part of a build, or to perform other actions at the start of every build.
Build tool plugins are invoked before a package is built in order to construct command invocations to run as part of the build.

A build tool plugin can provide two kinds of commands:

- term prebuild commands: commands that package manager runs before the build starts. Prebuild commands can generate an arbitrary number of output files with names that can't be predicted before running the command.
- term build commands: commands that package manager incorporates into the build system's dependency graph and runs at the appropriate time during the build based on the existence and timestamps of their predefined inputs and outputs.

> Note: If your goal is to provide an action that you can perform at any time and is not associated with a build, implement a command plugin.
> See <doc:WritingCommandPlugin> for details about creating a command plugin.

With both prebuild and build commands, it is important to note that the build tool plugin doesn't do the work, rather it constructs the commands that the build runs later, and it is those commands that perform the work.
The plugin can be quite small, and is often concerned with forming the command line for the build command that does the actual work.

A build tool plugin is available to the package that defines it, and if there is a corresponding plugin product, it is also available to any other package that has a direct dependency on the package.

### Build commands

Prefer to create a build command over a prebuild command when the paths of all of the inputs and outputs are known before the command runs.
Build tool commands are more efficient because they provide the build system the information needed to efficiently decide when the build should invoke them.

An example is a source translation tool that generates one output file (with a predictable name) for each input file.
Other examples include when the build command controls the names of the outputs without having to first run the tool.
In these cases the build system runs the commands only when some of the expected outputs are missing, or when the inputs have changed after the last time the command ran.
Build commands don't require a one-to-one correspondence between inputs and outputs; it is free to choose how many (if any) output files to create by examining the input target.

### Prebuild commands

Create a prebuild command only when the names of the output aren't known until the tool is run.
This is the case if the _contents_ of the input files (opposed to the input file names) determines the number and names of the output files, such as generating code based on the input of a configuration file.
The build system runs prebuild commands run before every build.
They should therefore do their own caching to minimize the work needed to avoid slowing down incremental builds.

### Declaring a build tool plugin in the package manifest

Declare a build tool plugin in the package manifest.
This is done using a `pluginTarget` entry in the `targets` section of the package.
Add a corresponding `plugin` entry the products section to make the plugin available to other packages.   

The following example illustrates defining a build tool named "MyBuildToolPlugin" that depends on the product `SomeTool`, and can be used from other packages:

```swift
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

The [plugin target](https://developer.apple.com/documentation/packagedescription/target/plugin(name:capability:dependencies:path:exclude:sources:)) declares the name and capability of the plugin, along with its dependencies.
The capability of `.buildTool()` is the declaration that this defines a build tool plugin.
The capability also indicates the entry point the plugin is expected to implement.

When you declare a `plugin` product, that makes the plugin visible to other packages that have a dependency on the package.
The name of the plugin doesn't have to match the name of the product, but they are often the same in order to avoid confusion.
Only list the name of the plugin the target provides.
If you only use the build tool plugin within the package, you don't need to declare a `plugin` product.

### Build tool target dependencies

The dependencies specify the command line tools available for use in commands constructed by the plugin.
Each dependency can be either an `executableTarget` or a `binaryTarget` target in the same package, or can be an `executable` product in another package.
In the example above, the plugin depends on the hypothetical _SomeTool_ product in the _sometool_ package on which the package that defines the plugin has a dependency.
Note that this does not necessarily mean that _SomeTool_ will have been built when the plugin is invoked. It means that the plugin can look up the path at which the tool will exist at the time any commands constructed by the plugin are run.

Executable dependencies are built for the host platform as part of the build, while binary dependencies are references to `artifactbundle` archives that contains prebuilt binaries (see [SE-305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md)).
Binary targets are often used when the tool is built using a different build system than package manager, or when building it on demand is prohibitively expensive or requires a special build environment.

### Implementing the build tool plugin script

By default, Swift Package Manager looks for the implementation of a declared plugin in a subdirectory of the `Plugins` directory named with the same name as the plugin target.
This can be overridden using the `path` parameter in the target declaration.

A plugin consists of one or more Swift source files.
Conform the main entry point of the build tool plugin script to the `BuildToolPlugin` protocol.

Similar to how a package manifest imports the *PackageDescription* module provided by package manager, a package plugin imports the *PackagePlugin* module. 
The *PackagePlugin* module contains the API through which the plugin receives information from package manager and communicates results back to it.
The plugin script can import *Foundation* and other standard libraries, but it cannot import other libraries.

The following example returns an instance of `buildCommand`, so the package manager incorporates it into the build system's command graph.
The build system runs it if any of the output files are missing, or if the contents of any of the input files have changed since the last time the command ran.

```swift
import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
  func createBuildCommands(context: PluginContext, 
                           target: Target) throws -> [Command] {
    // This plugin only runs for package targets that can have source files.
    guard let sourceFiles = target.sourceModule?.sourceFiles else { return [] }

    // Find the code generator tool to run (replace this with the actual one).
    let generatorTool = try context.tool(named: "my-code-generator")

    // Construct a build command for each source file with a particular suffix.
    return sourceFiles.map(\.url).compactMap {
        createBuildCommand(for: $0, in: context.pluginWorkDirectoryURL, with: generatorTool.url)
    }
  }

  func createBuildCommand(for inputPath: URL,
                          in outputDirectoryPath: URL,
                          with generatorToolPath: URL) -> Command? {
    // Skip any file that doesn't have the extension we're looking for
    // (replace this with the actual one).
    guard inputPath.pathExtension == "my-input-suffix" else { return .none }

    // Return a command that will run during the build to generate the output file.
    let inputName = inputPath.lastPathComponent
    let outputName = inputPath.deletingPathExtension().lastPathComponent + ".swift"
    let outputPath = outputDirectoryPath.appendingPathComponent(outputName)
    return .buildCommand(
        displayName: "Generating \(outputName) from \(inputName)",
        executable: generatorToolPath,
        arguments: ["\(inputPath)", "-o", "\(outputPath)"],
        inputFiles: [inputPath],
        outputFiles: [outputPath]
    )
  }
}
```

Build tool plugins are always applied to a target, which is provided as a parameter.
Only source module targets have source files, so a plugin that iterates over source files commonly tests that the target it was provided conforms to `SourceModuleTarget`.

A build tool plugin can also return commands of the type `prebuildCommand`.
These run before the build starts and can populate a directory with output files whose names are not known until the command runs:

```swift
import PackagePlugin
import Foundation

@main
struct MyBuildToolPlugin: BuildToolPlugin {
    
  func createBuildCommands(context: PluginContext, 
                           target: Target) throws -> [Command] {

    // This example configures `sometool` to write to a 
    // "GeneratedFiles" directory in the plugin work directory 
    // (which is unique for each plugin and target).
    let outputDir = context.pluginWorkDirectoryURL
        .appendingPathComponent("GeneratedFiles")
    try FileManager.default.createDirectory(
        at: outputDir,
        withIntermediateDirectories: true)

    // Return a command to run `sometool` as a prebuild command. 
    // It runs before every build and generates source files 
    // into an output directory provided by the build context.
    return [.prebuildCommand(
            displayName: "Running SomeTool",
            executable: try context.tool(named: "SomeTool").path,
            arguments: [ "--verbose", "--outdir", outputDir ],
            outputFilesDirectory: outputDir)
    ]
  }
}
```

In the case of prebuild commands, any dependencies must be binary targets, since these commands run before the build starts.

A build tool plugin can return a combination of build tool commands and prebuild commands.
After the plugin runs, the build system incorporates the build commands it provides into the build graph.
This may result in changes that require commands to run during the subsequent build.

The build system runs prebuild commands after the plugin runs, but before the build starts. 
Any files that are in the prebuild command's declared `outputFilesDirectory` are evaluated as if they had been source files in the target.
The prebuild command should add or remove files in this directory to reflect the results of having run the command.

The package manager supports generated Swift source files and resources as outputs, but it does not support non-Swift source files.
Any generated resources are processed as if they had been declared in the manifest with the `.process()` rule.
The intent is to eventually support any type of file that you could include as a source file in the target, and to let the plugin provide greater control over the downstream processing of generated files.

### Diagnostics

Plugin entry points are marked `throws`, and any errors thrown from the entry point cause the build system to mark the plugin invocation as failed.
Package manager presents the thrown error to the user, which should include a clear description of what went wrong.

Additionally, plugins can use the `Diagnostics` API in PackagePlugin to emit warnings and errors.
These optionally include references to file paths and line numbers in those files.

### Debugging and Testing

Package manager doesn't currently have any specific support for debugging and testing plugins.
Many plugins act as adapters that construct command lines for invoking the tools that do the real work.
In the cases in which there is non-trivial code in a plugin, a good approach is to factor out that code into separate source files that can be included in unit tests using symbolic links with relative paths.

### Xcode Extensions to the PackagePlugin API

When you invoke a plugin in Apple’s Xcode IDE, the plugins have access to a library module provided by Xcode called *XcodeProjectPlugin*. 
This module extends the *PackagePlugin* APIs to let plugins work on Xcode targets in addition to packages.

In order to write a plugin that works with packages in every environment, and that conditionally works with Xcode projects when run in Xcode, the plugin should conditionally import the *XcodeProjectPlugin* module when it is available.
For example:

```swift
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension MyCommandPlugin: XcodeCommandPlugin {

  // Entry point for creating build commands for targets in Xcode projects.
  func createBuildCommands(context: XcodePluginContext,
                           target: XcodeTarget) throws -> [Command] {
    // Find the code generator tool to run (replace this with the actual one).
    let generatorTool = try context.tool(named: "my-code-generator")

    // Construct a build command for each source file with a particular suffix.
    return target.inputFiles.map(\.url).compactMap {
        createBuildCommand(for: $0,
                           in: context.pluginWorkDirectoryURL,
                           with: generatorTool.url)
    }
  }
}
#endif
```

The `XcodePluginContext` input structure is similar to the `PluginContext` structure, except that it provides access to an Xcode project. 
The Xcode project uses Xcode naming and semantics for the project model, which is somewhat different from that of package manager.
Some of the underlying types, such as `FileList`, or `Path`, are the same for `PackagePlugin` and `XcodeProjectPlugin`.

If any targets are chosen in the Xcode user interface, Xcode passes their names as `--target` arguments to the plugin.

Other IDEs or custom environments that use the package manager could similarly provide modules that define new entry points and extend the functionality of the core `PackagePlugin` APIs.
