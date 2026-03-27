# Creating artifact bundles

Build and package your library as a cross-platform artifact bundle.

## Overview

Creating an artifact bundle involves building static libraries for each target platform, organizing them with headers and module maps, creating a JSON manifest, and packaging everything as a ZIP archive for distribution.

This guide walks you through the complete process step-by-step.

### Prerequisites

- Swift Package Manager (comes with Swift toolchain)
- Build tools for your library (e.g., Rust, C++ compiler, CMake)
- Basic understanding of target triples
- `zip` utility for creating archives

### Build your static libraries

First, compile your library as a static library (`.a` file) for each target platform you want to support.

#### Building a C++ library

```bash
# macOS x86_64
clang++ -c -arch x86_64 -o mylib_macos_x86.o mylib.cpp
ar rcs libMyLib-macos-x86_64.a mylib_macos_x86.o

# macOS ARM64
clang++ -c -arch arm64 -o mylib_macos_arm.o mylib.cpp
ar rcs libMyLib-macos-arm64.a mylib_macos_arm.o

# Linux x86_64 (using cross-compilation or Docker)
x86_64-linux-gnu-g++ -c -o mylib_linux_x86.o mylib.cpp
ar rcs libMyLib-linux-x86_64.a mylib_linux_x86.o
```

#### Building a Rust library

```bash
# macOS x86_64
cargo rustc --release --target x86_64-apple-darwin --crate-type=staticlib
# Output: target/x86_64-apple-darwin/release/libmylib.a

# macOS ARM64
cargo rustc --release --target aarch64-apple-darwin --crate-type=staticlib
# Output: target/aarch64-apple-darwin/release/libmylib.a

# Linux x86_64
cargo rustc --release --target x86_64-unknown-linux-gnu --crate-type=staticlib
# Output: target/x86_64-unknown-linux-gnu/release/libmylib.a

# Linux ARM64
cargo rustc --release --target aarch64-unknown-linux-gnu --crate-type=staticlib
# Output: target/aarch64-unknown-linux-gnu/release/libmylib.a
```

See <doc:BuildingCrossPlatformLibraries> for platform-specific build flags and considerations.

### Create the bundle directory structure

Create a bundle directly with a directory for the precompiled binaries and another for headers and modeule maps:

```bash
# Create the bundle directory
mkdir -p MyLibrary.artifactbundle/mylib
mkdir -p MyLibrary.artifactbundle/include
```

The directory structure this example builds looks like:

```bash
# MyLibrary.artifactbundle/
# ├── info.json
# ├── mylib/
# │   ├── libMyLib-macos-x86_64.a
# │   ├── libMyLib-macos-arm64.a
# │   ├── libMyLib-linux-x86_64.a
# │   └── libMyLib-linux-arm64.a
# └── include/
#     ├── MyLibrary.h
#     └── module.modulemap
```

### Copy platform-specific libraries

Copy your compiled static libraries with platform-specific names into the structure:

```bash 
cp build/macos-x86_64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-macos-x86_64.a
cp build/macos-arm64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-macos-arm64.a
cp build/linux-x86_64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-linux-x86_64.a
cp build/linux-arm64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-linux-arm64.a
```

### Add headers and module map

Copy your C/C++ header files, and create a module map to expose functions from those headers to Swift:

```bash
# Copy your C/C++ header files
cp include/MyLibrary.h MyLibrary.artifactbundle/include/

# Create a module.modulemap file
cat > MyLibrary.artifactbundle/include/module.modulemap << 'EOF'
module MyLibrary {
    header "MyLibrary.h"
    export *
}
EOF
```

> Note: The module name in `module.modulemap` should match what you want Swift to import.
If your header has a different name, adjust accordingly.

<!-- placeholder to reference what can go into a module map from here - doesn't exist yet -->

### Create the info.json manifest

This is the central manifest that tells Swift Package Manager about your bundle.

```bash
cat > MyLibrary.artifactbundle/info.json << 'EOF'
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
                },
                {
                    "path": "mylib/libMyLib-linux-arm64.a",
                    "supportedTriples": ["aarch64-unknown-linux-gnu"],
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
```

See <doc:ArtifactBundleManifestReference> for complete info.json specification.

### Create the ZIP archive

> Important:
> The `.artifactbundle` directory must be at the root of the ZIP archive, not nested in subdirectories.

```bash
# ✅ CORRECT: Create zip from parent directory
zip -r MyLibrary.artifactbundle.zip MyLibrary.artifactbundle/

# ❌ WRONG: Don't create from within a subdirectory
# cd build/
# zip -r MyLibrary.artifactbundle.zip MyLibrary.artifactbundle/
# This creates: build/MyLibrary.artifactbundle/ (extra level!)

# Verify the archive structure
unzip -l MyLibrary.artifactbundle.zip | head -n 20
```

### Verify archive structure

The first entries should look like:

```
Archive:  MyLibrary.artifactbundle.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  01-15-2025 10:30   MyLibrary.artifactbundle/
     1234  01-15-2025 10:30   MyLibrary.artifactbundle/info.json
        0  01-15-2025 10:30   MyLibrary.artifactbundle/lib/
```

### Common mistake: Extra directory levels

```
# ❌ Wrong structure (will fail):
Archive:  MyLibrary.artifactbundle.zip
        0  01-15-2025 10:30   build/                          ← Extra level!
        0  01-15-2025 10:30   build/MyLibrary.artifactbundle/
     1234  01-15-2025 10:30   build/MyLibrary.artifactbundle/info.json
```

If you see extra directories, recreate the archive:

```bash
# Fix incorrect archive
unzip MyLibrary.artifactbundle.zip
cd build/  # Navigate to where .artifactbundle is
zip -r ../MyLibrary.artifactbundle.zip MyLibrary.artifactbundle/
cd ..
```

### Calculate checksum

Swift Package Manager requires a SHA256 checksum for security:

```bash
swift package compute-checksum MyLibrary.artifactbundle.zip
```

Output example:
```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

### Upload to GitHub releases

This example uses the `gh` command line tool to create a release at GitHub and upload the zip file to that release:

```bash
# Create a GitHub release (requires gh CLI)
gh release create v1.0.0 \
    --title "MyLibrary v1.0.0" \
    --notes "Initial release" \
    MyLibrary.artifactbundle.zip
```

Alternately, manually create the release and upload the zip file through the GitHub web interface.

## Using the artifact bundle

Add the binary target to your Package.swift:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "MyApp", targets: ["MyApp"])
    ],
    dependencies: [],
    targets: [
        // Binary target referencing the artifact bundle
        .binaryTarget(
            name: "MyLibrary",
            url: "https://github.com/yourorg/mylib/releases/download/v1.0.0/MyLibrary.artifactbundle.zip",
            checksum: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2"
        ),

        // Your Swift target that uses the binary
        .target(
            name: "MyApp",
            dependencies: ["MyLibrary"]
        ),
    ]
)
```

Use in Swift code:

```swift
import MyLibrary

func example() {
    let result = myLibraryFunction()
    print("Result: \(result)")
}
```
