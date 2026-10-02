# Distributing executables to package plugins

Package prebuilt command-line tools in an artifact bundle so a package plugin can run them.

## Overview

An artifact bundle can hold executables as well as libraries.
A build tool plugin can run a bundled executable without building it from source.
This works well for tools that need a different binary on each platform.

A bundle uses the `executable` artifact type for this.
For the full manifest schema, read <doc:ArtifactBundleReference>.

### Structure the bundle

Put one executable for each platform in a directory in the bundle:

```
MyTool.artifactbundle/
├── info.json
└── bin/
    ├── mytool-macos-x86_64
    ├── mytool-macos-arm64
    ├── mytool-linux-x86_64
    └── mytool-linux-arm64
```

Describe each executable in `info.json`:

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "MyTool": {
            "type": "executable",
            "version": "1.0.0",
            "variants": [
                {
                    "path": "bin/mytool-macos-x86_64",
                    "supportedTriples": ["x86_64-apple-macosx"]
                },
                {
                    "path": "bin/mytool-macos-arm64",
                    "supportedTriples": ["arm64-apple-macosx"]
                },
                {
                    "path": "bin/mytool-linux-x86_64",
                    "supportedTriples": ["x86_64-unknown-linux-gnu"]
                },
                {
                    "path": "bin/mytool-linux-arm64",
                    "supportedTriples": ["aarch64-unknown-linux-gnu"]
                }
            ]
        }
    }
}
```

An executable variant doesn't use `staticLibraryMetadata`.
Every executable variant needs `supportedTriples`.
Swift Package Manager reports an error for an executable variant that omits it.

### Declare the binary target and plugin

Declare the bundle as a binary target.
Then list the binary target as a dependency of the plugin:

```swift
// Package.swift
let package = Package(
    name: "MyPlugin",
    products: [
        .plugin(name: "MyBuildToolPlugin", targets: ["MyBuildToolPlugin"])
    ],
    targets: [
        .binaryTarget(
            name: "MyTool",
            url: "https://github.com/org/mytool/releases/download/v1.0.0/MyTool.artifactbundle.zip",
            checksum: "<checksum>"
        ),
        .plugin(
            name: "MyBuildToolPlugin",
            capability: .buildTool(),
            dependencies: ["MyTool"]
        )
    ]
)
```

To compute the checksum, run `swift package compute-checksum` on the archive.

### Run the tool from the plugin

Ask the plugin context for the tool by name.
The context returns the URL of the executable that matches the build host.
Pass that URL to a build command:

```swift
// Plugins/MyBuildToolPlugin/plugin.swift
import Foundation
import PackagePlugin

@main
struct MyBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let tool = try context.tool(named: "MyTool")

        return [
            .buildCommand(
                displayName: "Running MyTool",
                executable: tool.url,
                arguments: ["--input", target.directoryURL.path],
                inputFiles: target.sourceFiles.map(\.url),
                outputFiles: []
            )
        ]
    }
}
```

The URL-based `tool.url` and `directoryURL` properties require a `// swift-tools-version` of 6.0 or later.
Earlier tools versions use the `path` properties, which are deprecated.

## See Also

- <doc:ArtifactBundleReference>
- <doc:Plugins>
