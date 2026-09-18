# Artifact Bundle Reference

A reference of the manifest schema inside an artifact bundle for binary targets.

## Overview

An artifact bundle is a directory with an `.artifactbundle` extension that holds one or more prebuilt binary artifacts.
It also holds an `info.json` manifest that describes those artifacts.
Swift Package Manager reads this manifest through `ArtifactsArchiveMetadata.parse(fileSystem:rootPath:)`, which looks for `info.json` at the root of the bundle.

This page documents the shape of `info.json` for `executable` and `staticLibrary` artifacts.
These are the two artifact types that `binaryTarget` declarations use for command-line tools and C-ABI static libraries.
For instructions on creating a C-language target that consumes a static library artifact bundle, see <doc:CreatingCLanguageTargets>.
For adding a binary target as a dependency, see <doc:AddingDependencies>.

## Top-level shape

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "<artifact-name>": { }
    }
}
```

- term schemaVersion: A string identifying the manifest schema version. Swift Package Manager accepts `1.0`, `1.1`, and `1.2`; any other value fails to parse. See [schemaVersion history](#schemaVersion-history) for what each version adds.
- term artifacts: A dictionary mapping an artifact name to an `Artifact` object. The name is the identifier package authors reference from a `binaryTarget` declaration.

## Artifact

```json
{
    "type": "executable",
    "version": "1.0.0",
    "variants": [ ]
}
```

- term type: The kind of artifact. See [Artifact type values](#Artifact-type-values).
- term version: A string with the artifact's version, in the form package authors use to select artifacts.
- term variants: An array of `Variant` objects, one per platform/architecture build of the artifact.

### Artifact type values

| Value | Description | Reference |
|---|---|---|
| `executable` | A command-line executable tool | [SE-0305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md) |
| `staticLibrary` | A C-ABI static library, with headers and an optional module map | [SE-0482](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md) |
| `swiftSDK` | A Swift SDK for cross-compilation | [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) |
| `crossCompilationDestination` | The original name for `swiftSDK`, which Swift Package Manager still accepts and warns about but doesn't formally deprecate. | [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) |
| `experimentalWindowsDLL` | Experimental support for Windows DLLs | No Swift Evolution proposal |

`swiftSDK` and `crossCompilationDestination` bundles also carry a sibling `swift-sdk.json` file with additional fields this page doesn't cover. See [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md) for the full `swiftSDK` schema.

`ArtifactType` doesn't have a `dynamicLibrary` case. [SE-0490](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0490-environment-constrained-shared-libraries.md) proposed adding one, along with a new `schemaVersion` value of `"1.2"`. That proposal never merged; it was returned for revision. Its proposed `"1.2"` is unrelated to the `1.2` that SE-0482 already shipped for `staticLibrary`. See [schemaVersion history](#schemaVersion-history) for the versions Swift Package Manager currently accepts.

## Variant

```json
{
    "path": "relative/path/to/binary",
    "supportedTriples": ["x86_64-apple-macosx"],
    "staticLibraryMetadata": { }
}
```

- term path: The path to the binary for this variant, relative to the bundle root.
- term supportedTriples: An optional array of target triple strings this variant supports. When present and a `binaryTarget` of type `executable` needs to run, Swift Package Manager rejects a variant whose `supportedTriples` don't include the host triple. SE-0305 originally required this field on every variant. Commit [`9386170fe`](https://github.com/swiftlang/swift-package-manager/commit/9386170fe) later made it optional.
- term staticLibraryMetadata: An optional `StaticLibraryMetadata` object. Absent for `executable` and other artifact types; present for `staticLibrary` variants that Swift targets need to import directly.

## StaticLibraryMetadata

```json
{
    "headerPaths": ["include"],
    "moduleMapPath": "include/simple.modulemap"
}
```

- term headerPaths: An array of paths, relative to the bundle root, to directories containing the library's public headers.
- term moduleMapPath: An optional path, relative to the bundle root, to a module map for the library. A Swift target needs this module map to import the library directly; without it, only C, C++, and Objective-C targets can consume the headers. The SE-0482 proposal text didn't make clear whether this path was relative like the other two. A [forum reply](https://forums.swift.org/t/se-0482-binary-static-library-dependencies/79634/7) confirmed that it is.

`StaticLibraryMetadata` supports exactly one module map per variant. There's no mechanism for a variant to reference more than one; see [this forum question](https://forums.swift.org/t/se-0482-binary-static-library-dependencies/79634/19) raised during SE-0482's review.

C++ static libraries work today only via a C-ABI shim. There's no dedicated field for C++ header or interop metadata. The [proposal author confirmed this](https://forums.swift.org/t/se-0482-binary-static-library-dependencies/79634/6): "You would be able to make this work with a C++ library as well but we can't guarantee that it would be ABI compatible with your deployment target."

Swift static libraries are a different case from C-ABI static libraries wrapped for Swift import. They're out of scope for this schema.

## Worked examples

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

The real fixture also includes Linux arm64, Windows arm64, FreeBSD arm64, and FreeBSD x86_64 variants; this excerpt keeps one variant per platform family for brevity. See the fixture file itself, exercised end-to-end by `Tests/FunctionalTests/StaticBinaryLibrary.swift`, for the complete list.

## Diagnostics

`ArtifactsArchiveMetadata.parse(fileSystem:rootPath:)` produces these errors.

If `info.json` doesn't exist at the bundle root, parsing fails with:

```
ArtifactsArchive info.json not found at '<rootPath>'
```

If `schemaVersion` isn't one of the accepted values, parsing fails with:

```
invalid `schemaVersion` of bundle manifest at `<path>`: <value>
```

If a JSON value has the wrong type, parsing fails with:

```
Type mismatch in ArtifactsArchive info.json at '<path>'. Key '<keyPath>' expected type '<type>'.
```

If a required key is missing, parsing fails with:

```
Missing required key '<key>' in ArtifactsArchive info.json at '<path>' in <location>.
```

If a required key is `null`, parsing fails with:

```
Expected non-null value of type '<type>' in ArtifactsArchive info.json at '<path>'. Key '<keyPath>' is null.
```

If the JSON itself is malformed, parsing fails with:

```
Invalid JSON in ArtifactsArchive info.json at '<path>': <description>
```

A common cause of the `schemaVersion` error is a typo or unsupported value in `info.json`. In one [forum thread](https://forums.swift.org/t/how-to-get-artifactbundles-working-on-windows/83165), a misleading `"does not contain a binary artifact"` error obscured an invalid `schemaVersion` value.

### Auditing static library artifacts

Swift Package Manager ships the `swift package experimental-audit-binary-artifact <path>` command, which scans a static library binary artifact for undefined symbols. The command explicitly refuses to run on Darwin and Windows hosts.

## schemaVersion history

| Version | Adds | Reference |
|---|---|---|
| `1.0` | Baseline: `executable` artifacts | [SE-0305](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md) |
| `1.1` | `swiftSDK`/`crossCompilationDestination` artifacts | [SE-0387](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md); commit [`d632f3605`](https://github.com/swiftlang/swift-package-manager/commit/d632f3605) |
| `1.2` | `staticLibrary` artifacts and `staticLibraryMetadata` | [SE-0482](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md); commit [`477466d3d`](https://github.com/swiftlang/swift-package-manager/commit/477466d3d) |

## See Also

- [SE-0305: Package Manager Binary Target Improvements](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md)
- [SE-0387: Swift SDKs for Cross-Compilation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md)
- [SE-0482: Binary Static Library Dependencies](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0482-swiftpm-static-library-binary-target-non-apple-platforms.md)
- <doc:CreatingCLanguageTargets>
- <doc:ModuleMapReference>
- <doc:DebuggingModuleMaps>
- <doc:AddingDependencies>
