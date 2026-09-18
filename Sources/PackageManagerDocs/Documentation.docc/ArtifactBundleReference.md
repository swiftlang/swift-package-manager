# Artifact Bundle Reference

Read and understand a JSON manifest in an artifact bundle.

## Overview

An artifact bundle is a directory with an `.artifactbundle` extension that holds one or more prebuilt binary artifacts.
At the top of that directory is an `info.json` manifest that describes the bundle's artifacts.

This article documents the schema of `info.json`.
The artifact types `executable` and `staticLibrary` are used by `binaryTarget` declarations for command-line tools and C-ABI static libraries.
For instructions on creating a C-language target that consumes a static library artifact bundle, read <doc:CreatingCLanguageTargets>.
To add a binary target as a dependency, read <doc:AddingDependencies>.

## Manifest structure

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "<artifact-name>": { }
    }
}
```

- term schemaVersion: A string that identifies the manifest schema version. Swift Package Manager accepts `1.0`, `1.1`, and `1.2`; any other value fails to parse. See [schemaVersion history](#schemaVersion-history) for the version differences.
- term artifacts: A dictionary that maps an artifact name to an `Artifact` object. The name is the identifier that package authors reference in a `binaryTarget` declaration.

## Artifact

```json
{
    "type": "executable",
    "version": "1.0.0",
    "variants": [ ]
}
```

- term type: The kind of artifact. See [Artifact type values](#Artifact-type-values).
- term version: A string that presents the artifact's version, matching the format that a developer uses to select the artifact.
- term variants: An array of `Variant` objects, one per platform/architecture build of the artifact.

### Artifact type values

| Value | Description | Reference |
|---|---|---|
| `executable` | A command-line executable tool | [SE-0305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md) |
| `staticLibrary` | A C-ABI static library, with headers and an optional module map | [SE-0482](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md) |
| `swiftSDK` | A Swift SDK for cross-compilation | [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) |
| `crossCompilationDestination` | The original name for `swiftSDK`, which Swift Package Manager still accepts and warns about but doesn't formally deprecate. | [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) |
| `experimentalWindowsDLL` | Experimental support for Windows DLLs | |

`swiftSDK` and `crossCompilationDestination` bundles also carry a sibling `swift-sdk.json` file with additional fields not covered in this reference. See [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) for the full `swiftSDK` schema.

`ArtifactType` doesn't have a `dynamicLibrary` case.

## Variant

```json
{
    "path": "relative/path/to/binary",
    "supportedTriples": ["x86_64-apple-macosx"],
    "staticLibraryMetadata": { }
}
```

- term path: The path to the binary for this variant, relative to the bundle root.
- term supportedTriples: An optional array of target triple strings this variant supports. When present and a `binaryTarget` of type `executable` needs to run, Swift Package Manager rejects a variant whose `supportedTriples` don't include the host triple.
- term staticLibraryMetadata: An optional `StaticLibraryMetadata` object, present for `staticLibrary` variants that Swift targets import.

## StaticLibraryMetadata

```json
{
    "headerPaths": ["include"],
    "moduleMapPath": "include/simple.modulemap"
}
```

- term headerPaths: An array of paths, relative to the bundle root, to directories that contain the library's public headers.
- term moduleMapPath: An optional path, relative to the bundle root, to a module map for the library. The module map allows Swift to import a library. Each variant supports exactly one module map.

## Manifest examples

### executable

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "protocol-buffer-compiler": {
            "type": "executable",
            "version": "3.5.1",
            "variants": [
                {
                    "path": "x86_64-apple-macosx/protoc",
                    "supportedTriples": ["x86_64-apple-macosx"]
                },
                {
                    "path": "x86_64-unknown-linux-gnu/protoc",
                    "supportedTriples": ["x86_64-unknown-linux-gnu"]
                }
            ]
        }
    }
}
```

### staticLibrary

A multi-platform, multi-architecture static library, adapted from `Fixtures/BinaryLibraries/Static/Package1/Simple.artifactbundle/info.json`:

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "simple": {
            "type": "staticLibrary",
            "version": "1.0.0",
            "variants": [
                {
                    "path": "dist/macOS/libSimple.a",
                    "supportedTriples": ["arm64-apple-macosx", "x86_64-apple-macosx"],
                    "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/simple.modulemap"
                    }
                },
                {
                    "path": "dist/linux/libSimple_x86_64.a",
                    "supportedTriples": ["x86_64-unknown-linux-gnu"],
                    "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/simple.modulemap"
                    }
                },
                {
                    "path": "dist/windows/Simple_x86_64.lib",
                    "supportedTriples": ["x86_64-unknown-windows-msvc"],
                    "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/simple.modulemap"
                    }
                }
            ]
        }
    }
}
```

The fixture also includes Linux `arm64`, Windows `arm64`, FreeBSD `arm64`, and FreeBSD `x86_64` variants. This example shares one variant per platform family for brevity.

### Auditing static library artifacts

Swift Package Manager ships the `swift package experimental-audit-binary-artifact <path>` command, which scans a static library binary artifact for undefined symbols.

## schemaVersion history

| Version | Adds | Reference |
|---|---|---|
| `1.0` | Baseline: `executable` artifacts | [SE-0305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md) |
| `1.1` | `swiftSDK`/`crossCompilationDestination` artifacts | [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) |
| `1.2` | `staticLibrary` artifacts and `staticLibraryMetadata` | [SE-0482](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md) |

## See Also

- [SE-0305: Package Manager Binary Target Improvements](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md)
- [SE-0387: Swift SDKs for Cross-Compilation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md)
- [SE-0482: Binary Static Library Dependencies](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md)
- <doc:CreatingCLanguageTargets>
- <doc:ModuleMapReference>
- <doc:DebuggingModuleMaps>
- <doc:AddingDependencies>
