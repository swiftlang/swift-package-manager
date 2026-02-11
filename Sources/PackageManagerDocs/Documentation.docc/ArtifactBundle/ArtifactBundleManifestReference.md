# Artifact bundle manifest reference

Technical specification for the info.json manifest file.

## Overview

The `info.json` file is the manifest that describes an artifact bundle's contents, structure, and platform support. This reference documents the complete schema with all field definitions and requirements.

## Schema structure

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "<ArtifactName>": {
            "type": "staticLibrary" | "executable" | "swiftSDK",
            "version": "<version-string>",
            "variants": [
                {
                    "path": "<relative-path-to-binary>",
                    "supportedTriples": ["<target-triple>", ...],
                    "staticLibraryMetadata": {
                        "headerPaths": ["<header-directory>", ...],
                        "moduleMapPath": "<path-to-modulemap>"
                    }
                }
            ]
        }
    }
}
```

## Field reference

| Field | Required | Description |
|-------|----------|-------------|
| `schemaVersion` | Yes | Schema version: `"1.0"`, `"1.1"`, or `"1.2"` |
| `artifacts` | Yes | Object mapping artifact names to definitions |
| `type` | Yes | Type of binary: `staticLibrary`, `executable`, or `swiftSDK` |
| `version` | Yes | Version string (such as `"1.0.0"`) |
| `variants` | Yes | Array of platform-specific binaries |
| `path` | Yes | Relative path from bundle root to binary |
| `supportedTriples` | Optional | Array of target triples this binary supports |
| `staticLibraryMetadata` | Conditional | Required for `staticLibrary` type |
| `headerPaths` | Yes (for static) | Directories containing headers (relative to bundle root) |
| `moduleMapPath` | Optional | Path to `module.modulemap` file |

## Schema versions

Swift Package Manager's artifact bundle format supports multiple schema versions:

| Version | Status | Recommendation |
|---------|--------|----------------|
| `"1.0"` | ✅ **Stable** | **Recommended** - Maximum compatibility |
| `"1.1"` | ✅ **Stable** | Use if needed for specific features |
| `"1.2"` | ✅ **Stable** | Use if needed for specific features |

**Best practice**: Use `"schemaVersion": "1.0"` for maximum compatibility unless you specifically need features from later versions.

## Platform target triples

### Apple platforms

| Platform | Architecture | Target Triple |
|----------|--------------|---------------|
| macOS | x86_64 (Intel) | `x86_64-apple-macosx` |
| macOS | ARM64 (Apple Silicon) | `arm64-apple-macosx` |
| iOS Device | ARM64 | `arm64-apple-ios` |
| iOS Simulator | x86_64 (Intel Mac) | `x86_64-apple-ios` |
| iOS Simulator | ARM64 (Apple Silicon) | `arm64-apple-ios-simulator` |
| Mac Catalyst | x86_64 | `x86_64-apple-ios-macabi` |
| Mac Catalyst | ARM64 | `arm64-apple-ios-macabi` |

### Linux platforms

| Distribution | C Library | Architecture | Target Triple |
|--------------|-----------|--------------|---------------|
| Ubuntu, Debian, RHEL | glibc | x86_64 | `x86_64-unknown-linux-gnu` |
| Ubuntu, Debian, RHEL | glibc | ARM64 | `aarch64-unknown-linux-gnu` |
| Alpine Linux | musl | x86_64 | `x86_64-swift-linux-musl` |
| Alpine Linux | musl | ARM64 | `aarch64-swift-linux-musl` |

> Note: When compiling for musl targets, use the Swift-specific triple format (`x86_64-swift-linux-musl`) to distinguish it from a "normal" musl setup, such as Alpine, which uses the Rust/LLVM format (`x86_64-unknown-linux-musl`).

### Windows platforms

| Architecture | Target Triple |
|--------------|---------------|
| x86_64 | `x86_64-unknown-windows-msvc` |
| ARM64 | `aarch64-unknown-windows-msvc` |

## Optional fields

### supportedTriples (optional)

The `supportedTriples` field can be omitted for universal binaries or when all platforms are supported, but it's recommended to always include it for clarity.

**When to include `supportedTriples`** (recommended):
- ✅ Platform-specific binaries (one per architecture)
- ✅ Different binaries for macOS vs Linux vs iOS
- ✅ When you want explicit control over platform selection

### moduleMapPath (optional)

The `moduleMapPath` field is optional for simple C headers where Swift can auto-generate the module map, but it's recommended for most cases.

**When to include `moduleMapPath`** (recommended):
- ✅ C++ headers (namespaces, templates, classes)
- ✅ Complex C headers with macros or conditional compilation
- ✅ Multiple interdependent headers
- ✅ Custom module naming required

**When to omit `moduleMapPath`** (simple cases):
- ⚠️ Simple C headers with standard types only
- ⚠️ Single header file with no dependencies

**Best practice**: Include `moduleMapPath` for all static libraries with headers.

See <doc:ModuleMaps> for information on creating Module Maps.

## Complete example

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "MyLibrary": {
            "type": "staticLibrary",
            "version": "1.0.0",
            "variants": [
                {
                    "path": "mylib/libMyLib-macos-x86_64.a",
                    "supportedTriples": ["x86_64-apple-macosx"],
                    "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/module.modulemap"
                    }
                },
                {
                    "path": "mylib/libMyLib-macos-arm64.a",
                    "supportedTriples": ["arm64-apple-macosx"],
                    "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/module.modulemap"
                    }
                },
                {
                    "path": "mylib/libMyLib-linux-x86_64.a",
                    "supportedTriples": ["x86_64-unknown-linux-gnu"],
                    "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/module.modulemap"
                    }
                }
            ]
        }
    }
}
```
