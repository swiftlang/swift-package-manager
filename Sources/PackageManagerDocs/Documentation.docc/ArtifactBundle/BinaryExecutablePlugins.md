# Using Advanced Artifact Bundle Features

Include pre-compiled binaries in artifactBundles to use from Swift Package Plugins

## Overview

Package executable binaries alongside or instead of libraries to support build tool plugins and custom workflows.

Artifact bundles can distribute executable binaries using the `executable` artifact type.
This approach works particularly well for build tool plugins that need platform-specific command-line tools.

### Structure executable artifacts

Create a bundle with platform-specific executables in a `bin` directory:

```
MyTool.artifactbundle/
├── info.json
└── bin/
    ├── mytool-macos-x86_64
    ├── mytool-macos-arm64
    ├── mytool-linux-x86_64
    └── mytool-linux-arm64
```

Define the executables in your manifest using the `executable` type:

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

Executable artifacts reference the binary directly and don't require `staticLibraryMetadata`.

### Use executables in build tool plugins

Access executable artifacts through the plugin context and pass them to build commands:

```swift
// Plugins/MyBuildToolPlugin/plugin.swift
import PackagePlugin

@main
struct MyBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        // Get the path to the binary tool
        let toolPath = try context.tool(named: "MyTool").path

        return [
            .buildCommand(
                displayName: "Running MyTool",
                executable: toolPath,
                arguments: ["--input", target.directory],
                inputFiles: target.sourceFiles.map(\.path),
                outputFiles: []
            )
        ]
    }
}
```

Define the plugin dependency in your package manifest:

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
            checksum: "abc123..."
        ),
        .plugin(
            name: "MyBuildToolPlugin",
            capability: .buildTool(),
            dependencies: ["MyTool"]
        )
    ]
)
```

### Handle macOS notarization limitations

Artifact bundles don't support macOS notarization for executables. Apple's notarization service accepts app bundles, disk images, and installer packages, but Swift Package Manager only accepts `.zip` archives for artifact bundles. Non-bundled executables within `.zip` files can't be notarized through standard workflows.

**Workarounds**:

- For Apple-only tools: Use XCFrameworks instead if notarization is required
- For cross-platform tools: Accept that macOS users may see Gatekeeper warnings on first run
- Code signing without notarization: Sign the executable before zipping to provide some security validation
- Document manual approval: Instruct users to approve the binary via System Settings → Privacy & Security

**When to choose XCFrameworks**:

- Distributing executables that must run without user interaction on macOS
- Commercial software requiring notarization for user trust
- Enterprise environments with strict security policies

