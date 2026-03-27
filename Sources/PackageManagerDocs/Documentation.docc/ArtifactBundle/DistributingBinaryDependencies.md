# Distributing binary dependencies

Use artifact bundles to distribute pre-compiled libraries across all Swift platforms.

## Overview

**Artifact bundles** are Swift Package Manager's format for distributing pre-compiled binary dependencies.
When you're building pre-compiled libraries for Apple platforms, use XCFrameworks.
Artifact bundles support all Swift platforms, including Linux, making them ideal for cross-platform libraries.

### When to use artifact bundles

Artifact bundles are particularly useful when:

- You want to distribute a library without requiring users to build from source.
- Your library has complex build requirements (C++, Rust, CMake, and so on).
- You need to distribute large C/C++/Rust libraries that take significant time to compile.
- You want to ensure consistent builds across development, CI/CD, and production environments.

## What is an artifact bundle?

An artifact bundle is a directory with a `.artifactbundle` extension containing:

1. **Binary artifacts** - Static libraries, executables, or Swift SDK toolchains for each platform
2. **Headers** - C/C++ header files and module maps (for static libraries)
3. **Manifest** - `info.json` describing the bundle structure
4. **License** - Optional license files

The bundle is zipped and distributed via URL (typically from a GitHub release).

### Directory structure

```
MyLibrary.artifactbundle/
├── info.json
├── mylib/
│   ├── libMyLib-macos-x86_64.a
│   ├── libMyLib-macos-arm64.a
│   ├── libMyLib-linux-x86_64.a
│   └── libMyLib-linux-arm64.a
└── include/
    ├── MyLibrary.h
    └── module.modulemap
```

## Quick start for library creators

Create your first artifact bundle:

```bash
# 1. Build your static libraries for each platform
make build-all  # or cargo build --release --target <triple>

# 2. Create bundle structure
mkdir -p MyLib.artifactbundle/{lib,include}

# 3. Copy binaries and headers
cp build/macos-arm64/libmylib.a MyLib.artifactbundle/lib/libMyLib-macos-arm64.a
cp build/macos-x86_64/libmylib.a MyLib.artifactbundle/lib/libMyLib-macos-x86_64.a
cp include/*.h MyLib.artifactbundle/include/

# 4. Create module map
cat > MyLib.artifactbundle/include/module.modulemap << 'EOF'
module MyLib {
    header "mylib.h"
    export *
}
EOF

# 5. Create info.json
cat > MyLib.artifactbundle/info.json << 'EOF'
{
  "schemaVersion": "1.0",
  "artifacts": {
    "MyLib": {
      "type": "staticLibrary",
      "version": "1.0.0",
      "variants": [
        {
          "path": "mylib/libMyLib-macos-arm64.a",
          "supportedTriples": ["arm64-apple-macosx"],
          "staticLibraryMetadata": {
            "headerPaths": ["include"],
            "moduleMapPath": "include/module.modulemap"
          }
        },
        {
          "path": "mylib/libMyLib-macos-x86_64.a",
          "supportedTriples": ["x86_64-apple-macosx"],
          "staticLibraryMetadata": {
            "headerPaths": ["include"],
            "moduleMapPath": "include/module.modulemap"
          }
        }
      ]
    }
  }
}
EOF

# 6. Create ZIP and compute checksum
zip -r MyLib.artifactbundle.zip MyLib.artifactbundle/
swift package compute-checksum MyLib.artifactbundle.zip

# 7. Upload to GitHub releases
gh release create v1.0.0 MyLib.artifactbundle.zip
```

## Quick start for library consumers

Use an artifact bundle in your Swift package:

```swift
// Add to your Package.swift
.binaryTarget(
    name: "MyLib",
    url: "https://github.com/org/repo/releases/download/v1.0.0/MyLib.artifactbundle.zip",
    checksum: "<checksum-from-step-6>"
),

// Use in your target
.target(
    name: "MyApp",
    dependencies: ["MyLib"]
)
```

```swift
// Import and use in Swift code
import MyLib

let result = myLibFunction()
```

## How Swift Package Manager processes artifact bundles

When you add an artifact bundle dependency, Swift Package Manager automatically:

1. **Downloads** the artifact bundle (or uses cached version).
2. **Verifies** the checksum for security.
3. **Selects** the correct platform variant for your build target.
4. **Extracts** headers and module maps.
5. **Configures** build settings (header search paths, module maps, linker flags).
6. **Links** the static library into your executable.

You don't need to manually configure header paths, module maps, or linker flags.
Swift Package Manager handles everything automatically.

## Topics

### Building artifact bundles

- <doc:CreatingArtifactBundles>
- <doc:BuildingCrossPlatformLibraries>

### Validating bundles

- <doc:ProcessingArtifactBundles>
- <doc:TroubleshootingArtifactBundles>

### Artifact Bundle Reference

- <doc:ArtifactBundleManifestReference>

### Using bundles with Package Manager Plugins

- <doc:BinaryExecutablePlugins>
