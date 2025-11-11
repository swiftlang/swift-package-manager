# ``PackagePlugin``

Create plugins that extend the Swift Package Manager.

<!-- swift package --disable-sandbox preview-documentation --target PackagePlugin -->
## Overview

Build tool plugins generate source files as part of a build, or perform other actions at the start of every build.
The package manager invokes build tool plugins before a package is built in order to construct command invocations to run as part of the build.
Command plugins provide actions that users can perform at any time and aren't associated with a build.

Read [Writing a build tool plugin](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/WritingBuildToolPlugin) to learn how to create build tool plugins, or [Writing a command plugin](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/WritingCommandPlugin) to learn how to create command plugins.

## Topics

### Implementing Command Plugins

- ``CommandPlugin``
- ``PluginContext``
- ``Plugin``

### Extracting Arguments

- ``ArgumentExtractor``

### Implementing Build Plugins

- ``BuildToolPlugin``
- ``PluginContext``
- ``Target``
- ``Command``

### Interacting with Package Manager

- ``PackageManager``
- ``PackageManagerProxyError``

### Inspecting the Package Representation

- ``Package``
- ``ToolsVersion``
- ``PackageOrigin``
- ``PackageDependency``
- ``Product``
- ``ExecutableProduct``
- ``LibraryProduct``

### Inspecting Package Targets

- ``Target``
- ``TargetDependency``
- ``SourceModuleTarget``
- ``ModuleKind``
- ``SwiftSourceModuleTarget``
- ``ClangSourceModuleTarget``
- ``BinaryArtifactTarget``
- ``SystemLibraryTarget``

### Inspecting Package Files

- ``FileList``
- ``File``
- ``FileType``

- ``Path``
- ``PathList``

### Plugin Diagnostics and Errors

- ``Diagnostics``
- ``PluginContextError``
- ``PluginDeserializationError``
