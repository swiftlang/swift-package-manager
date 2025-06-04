# Writing a build tool plugin

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

The first step when writing a package plugin is to decide what kind of plugin you need.  If your goal is to generate source files that should be part of a build, or to perform other actions at the start of every build, implement a build tool plugin.  If your goal is to provide actions that users can perform at any time and that are not associated with a build, implement a command plugin.

A plugin is available to the package that defines it, and if there is a corresponding plugin product, it is also available to any other package that has a direct dependency on the package.

### Build tool plugins

Build tool plugins are invoked before a package is built in order to construct command invocations to run as part of the build.  There are two kinds of commands that a build tool plugin can return:

- prebuild commands — are run before the build starts and can generate an arbitrary number of output files with names that can't be predicted before running the command
- build commands — are incorporated into the build system's dependency graph and will run at the appropriate time during the build based on the existence and timestamps of their predefined inputs and outputs

Build commands are preferred over prebuild commands when the paths of all of the inputs and outputs are known before the command runs, since they allow the build system to more efficiently decide when they should be run.  This is actually quite common.  Examples include source translation tools that generate one output file (with a predictable name) for each input file, or other cases where the plugin can control the names of the outputs without having to first run the tool.  In this case the build system can run the command only when some of the outputs are missing or when the inputs have changed since the last time the command ran.  There doesn't have to be a one-to-one correspondence between inputs and outputs; a plugin is free to choose how many (if any) output files to create by examining the input target using any logic it wants to.

Prebuild commands should be used only when the names of the outputs are not known until the tool is run — this is the case if the _contents_ of the input files (as opposed to just their names) determines the number and names of the output files.  Prebuild commands have to run before every build, and should therefore do their own caching to do as little work as possible to avoid slowing down incremental builds.

In either case, it is important to note that it is not the plugin itself that does all the work of the build command — rather, the plugin constructs the commands that will later need to run, and it is those commands that perform the actual work.  The plugin itself is usually quite small and is mostly concerned with forming the command line for the build command that does the actual work.

#### Declaring a build tool plugin in the package manifest

Like all kinds of package plugins, build tool plugins are declared in the package manifest.  This is done using a `pluginTarget` entry in the `targets` section of the package.  If the plugin should be visible to other packages, there needs to be a corresponding `plugin` entry in the `products` section as well:

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

The `plugin` target declares the name and capability of the plugin, along with its dependencies.  The capability of `.buildTool()` is what declares it as a build tool plugin as opposed to any other kind of plugin — this also determines what entry point the plugin is expected to implement (as described below).

The Swift script files that implement the logic of the plugin are expected to be in a directory named the same as the plugin, located under the `Plugins` subdirectory of the package.  This can be overridden with a `path` parameter in the `pluginTarget`.

The `plugin` product is what makes the plugin visible to other packages that have dependencies on the package that defines the plugin.  The name of the plugin doesn't have to match the name of the product, but they are often the same in order to avoid confusion.  The plugin product should list only the name of the plugin target it vends.  If a built tool plugin is used only within the package that declares it, there is no need to declare a `plugin` product.

#### Build tool target dependencies

The dependencies specify the command line tools that will be available for use in commands constructed by the plugin.  Each dependency can be either an `executableTarget` or a `binaryTarget` target in the same package, or can be an `executable` product in another package (there are no binary products in package manager).  In the example above, the plugin depends on the hypothetical _SomeTool_ product in the _sometool_ package on which the package that defines the plugin has a dependency.  Note that this does not necessarily mean that _SomeTool_ will have been built when the plugin is invoked — it only means that the plugin will be able to look up the path at which the tool will exist at the time any commands constructed by the plugin are run.

Executable dependencies are built for the host platform as part of the build, while binary dependencies are references to `artifactbundle` archives that contains prebuilt binaries (see [SE-305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md)).  Binary targets are often used when the tool is built using a different build system than package manager, or when building it on demand is prohibitively expensive or requires a special build environment.

#### Implementing the build tool plugin script

By default, Swift Package Manager looks for the implementation of a declared plugin in a subdirectory of the `Plugins` directory named with the same name as the plugin target.  This can be overridden using the `path` parameter in the target declaration.

A plugin consists of one or more Swift source files, and the main entry point of the build tool plugin script is expected to conform to the `BuildToolPlugin` protocol.

Similar to how a package manifest imports the *PackageDescription* module provided by package manager, a package plugin imports the *PackagePlugin* module which contains the API through which the plugin receives information from package manager and communicates results back to it.

```swift
import PackagePlugin

@main
struct MyPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target.sourceModule else { return [] }
        let inputFiles = target.sourceFiles.filter({ $0.path.extension == "dat" })
        return try inputFiles.map {
            let inputFile = $0
            let inputPath = inputFile.path
            let outputName = inputPath.stem + ".swift"
            let outputPath = context.pluginWorkDirectory.appending(outputName)
            return .buildCommand(
                displayName: "Generating \(outputName) from \(inputPath.lastComponent)",
                executable: try context.tool(named: "SomeTool").path,
                arguments: [ "--verbose", "\(inputPath)", "\(outputPath)" ],
                inputFiles: [ inputPath, ],
                outputFiles: [ outputPath ]
            )
        }
    }
}
```

The plugin script can import *Foundation* and other standard libraries, but in the current version of package manager, it cannot import other libraries.

In this example, the returned command is of the type `buildCommand`, so it will be incorporated into the build system's command graph and will run if any of the output files are missing or if the contents of any of the input files have changed since the last time the command ran.

Note that build tool plugins are always applied to a target, which is passed in the parameter to the entry point.  Only source module targets have source files, so a plugin that iterates over source files will commonly test that the target it was given conforms to `SourceModuleTarget`.

A build tool plugin can also return commands of the type `prebuildCommand`, which run before the build starts and can populate a directory with output files whose names are not known until the command runs:

```swift
import PackagePlugin
import Foundation

@main
struct MyBuildToolPlugin: BuildToolPlugin {
    
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        // This example configures `sometool` to write to a "GeneratedFiles" directory in
        // the plugin work directory (which is unique for each plugin and target).
        let outputDir = context.pluginWorkDirectory.appending("GeneratedFiles")
        try FileManager.default.createDirectory(atPath: outputDir.string,
            withIntermediateDirectories: true)

        // Return a command to run `sometool` as a prebuild command. It will be run before
        // every build and generates source files into an output directory provided by the
        // build context.
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

Note that a build tool plugin can return a combination of build tool commands and prebuild commands.  After the plugin runs, any build commands are incorporated into the build graph, which may result in changes that require commands to run during the subsequent build.

Any prebuild commands are run after the plugin runs but before the build starts, and any files that are in the prebuild command's declared `outputFilesDirectory` will be evaluated as if they had been source files in the target.  The prebuild command should add or remove files in this directory to reflect the results of having run the command.

The current version of the Swift Package Manager supports generated Swift source files and resources as outputs, but it does not yet support non-Swift source files.  Any generated resources are processed as if they had been declared in the manifest with the `.process()` rule.  The intent is to eventually support any type of file that could have been included as a source file in the target, and to let the plugin provide greater controls over the downstream processing of generated files.

### Diagnostics

Plugin entry points are marked `throws`, and any errors thrown from the entry point cause the plugin invocation to be marked as having failed.  The thrown error is presented to the user, and should include a clear description of what went wrong.

Additionally, plugins can use the `Diagnostics` API in PackagePlugin to emit warnings and errors that optionally include references to file paths and line numbers in those files.

### Debugging and Testing

package manager doesn't currently have any specific support for debugging and testing plugins.  Many plugins act only as adapters that construct command lines for invoking the tools that do the real work — in the cases in which there is non-trivial code in a plugin, the best current approach is to factor out that code into separate source files that can be included in unit tests in the plugin package via symbolic links with relative paths.

### Xcode Extensions to the PackagePlugin API

When invoked in Apple’s Xcode IDE, plugins have access to a library module provided by Xcode called *XcodeProjectPlugin* — this module extends the *PackagePlugin* APIs to let plugins work on Xcode targets in addition to packages.

In order to write a plugin that works with packages in every environment and that conditionally works with Xcode projects when run in Xcode, the plugin should conditionally import the *XcodeProjectPlugin* module when it is available.  For example:

```swift
import PackagePlugin

@main
struct MyCommandPlugin: CommandPlugin {
    /// This entry point is called when operating on a Swift package.
    func performCommand(context: PluginContext, arguments: [String]) throws {
        debugPrint(context)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension MyCommandPlugin: XcodeCommandPlugin {
    /// This entry point is called when operating on an Xcode project.
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        debugPrint(context)
    }
}
#endif
```

The `XcodePluginContext` input structure is similar to the regular `PluginContext` structure, except that it provides access to an Xcode project that uses Xcode naming and semantics for the project model (which is somewhat different from that of package manager).  Some of the underlying types, such as `FileList`, `Path`, etc are the same for `PackagePlugin` and `XcodeProjectPlugin` types.

If any targets are chosen in the Xcode user interface, Xcode passes their names as `--target` arguments to the plugin.

It is expected that other IDEs or custom environments that use package manager could similarly provide modules that define new entry points and extend the functionality of the core `PackagePlugin` APIs.

