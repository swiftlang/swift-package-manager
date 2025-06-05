# Plugins

@Metadata {
    @Available("Swift", introduced: "5.6")
}

Extend package manager functionality with build or command plugins.  

## Overview

Some of Swift Package Manager's functionality can be extended through _plugins_.
Write package plugins using the `PackagePlugin` API provided by the Swift Package Manager. <!-- link to docs needed -->
This is similar to how the package manifest is implemented — as Swift code that runs as needed in order to produce the information package manager needs.

Package manager defines two extension points for plugins:

- term Build Plugin: Custom build tool tasks that provide commands to run before or during the build.
  See <doc:EnableBuildPlugin> to see how to add an existing build plugin, or <doc:WritingBuildToolPlugin> to write your own.

- term Command Plugin: Custom commands that you run using the `swift package` command line interface.
  See <doc:EnableCommandPlugin> to see how to add an existing command plugin, or <doc:WritingCommandPlugin> to write your own.

### Plugin Capabilities

Plugins have access to a representation of the package model.
Command plugins can also invoke services provided by package manager to build and test products and targets defined in the package to which the plugin is applied.

Every plugin runs as a separate process from the package manager. 
On platforms that support sandboxing, package manager wraps the plugin in a sandbox that prevents network access and attempts to write to arbitrary locations in the file system.
All plugins can write to a temporary directory.

Custom command plugins that need to modify the package source code can specify this requirement.
If the user approves, package manager grants write access to the package directory.
Build tool plugins can't modify the package source code.

### Creating Plugins

When creating a plugin, represent a plugin in the package manifest as a target of the `pluginTarget` type.
If it should be available to other packages, also include a corresponding `pluginProduct` target.
Source code for a plugin is normally located in a directory under the `Plugins` directory in the package, but this can be customized.

A plugin declares which extension point it implements by defining the plugin's _capability_.
This determines the entry point through which package manager will call it, and determines which actions the plugin can perform.

### References

- "Meet Swift Package plugins" [WWDC22 session](https://developer.apple.com/videos/play/wwdc2022-110359)
- "Create Swift Package plugins" [WWDC22 session](https://developer.apple.com/videos/play/wwdc2022-110401)

## Topics

### Enabling Plugins

- <doc:EnableCommandPlugin>
- <doc:EnableBuildPlugin>

### Writing Plugins

- <doc:WritingCommandPlugin>
- <doc:WritingBuildToolPlugin>
