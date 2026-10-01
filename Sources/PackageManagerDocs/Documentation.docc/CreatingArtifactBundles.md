# Creating artifact bundles

Package prebuilt static libraries for several platforms as one artifact bundle.

## Overview

An artifact bundle holds prebuilt binaries, their headers, and a JSON manifest.
Package authors reference the bundle from a `binaryTarget` declaration.

To create a bundle, you do the following:

1. Build a static library for each platform you support.
2. Lay out the libraries, headers, and a module map in a bundle directory.
3. Write the `info.json` manifest.
4. Archive the bundle and compute its checksum.

This article builds a bundle for a C or C++ library.
The bundle's `staticLibrary` artifact type is the one this article uses.
To see every field in the manifest, read <doc:ArtifactBundleReference>.

### Prerequisites

- A Swift toolchain, which includes Swift Package Manager.
- A C or C++ compiler, or a build system such as CMake.
- A basic understanding of target triples.
- The `zip` utility.

### Build your static libraries

Compile your library as a static library for each platform you want to support.
Each build produces one `.a` file.

The following commands build a C++ library:

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

### Create the bundle directory structure

Create a directory with the `.artifactbundle` extension.
Add one directory for the libraries and one for the headers and module map:

```bash
mkdir -p MyLibrary.artifactbundle/mylib
mkdir -p MyLibrary.artifactbundle/include
```

When you finish all the steps, the bundle looks like this:

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

### Copy the platform-specific libraries

Copy each compiled library into the `mylib` directory.
Give each file a name that identifies its platform and architecture:

```bash
cp build/macos-x86_64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-macos-x86_64.a
cp build/macos-arm64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-macos-arm64.a
cp build/linux-x86_64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-linux-x86_64.a
cp build/linux-arm64/libmylib.a MyLibrary.artifactbundle/mylib/libMyLib-linux-arm64.a
```

### Add the headers and a module map

Copy your C or C++ headers.
Then create a module map that exposes those headers to Swift:

```bash
cp include/MyLibrary.h MyLibrary.artifactbundle/include/

cat > MyLibrary.artifactbundle/include/module.modulemap << 'EOF'
module MyLibrary {
    header "MyLibrary.h"
    export *
}
EOF
```

The module name is the name that Swift code uses in `import`.
If your header has a different name, adjust the `header` line.

To learn what a module map can express, read <doc:ModuleMaps> and <doc:ModuleMapReference>.
If a Swift target can't import your library, read <doc:DebuggingModuleMaps>.

### Create the info.json manifest

The `info.json` file sits at the root of the bundle.
It tells Swift Package Manager which binary to use on each platform.

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

Include `supportedTriples` on every variant.
For a `staticLibrary` artifact, Swift Package Manager never selects a variant that omits it, and it doesn't report an error.
For the full schema, read <doc:ArtifactBundleReference>.

### Try the bundle locally

Before you archive the bundle, test it in a package.
A `binaryTarget` can point at the bundle directory with the `path` parameter:

```swift
.binaryTarget(
    name: "MyLibrary",
    path: "MyLibrary.artifactbundle"
)
```

Build the package on each platform that you listed in the manifest.

### Create the archive

Run `zip` from the directory that contains the bundle.
Put the `.artifactbundle` directory at the top of the archive:

```bash
zip -r MyLibrary.artifactbundle.zip MyLibrary.artifactbundle/
```

List the archive contents to check the structure:

```bash
unzip -l MyLibrary.artifactbundle.zip | head -n 20
```

The first entries look like this:

```
Archive:  MyLibrary.artifactbundle.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  01-15-2025 10:30   MyLibrary.artifactbundle/
     1234  01-15-2025 10:30   MyLibrary.artifactbundle/info.json
        0  01-15-2025 10:30   MyLibrary.artifactbundle/mylib/
```

> Note: Swift Package Manager tolerates one extra level.
> If an archive has a single top-level directory that contains the `.artifactbundle` directory, such as `build/MyLibrary.artifactbundle`, Swift Package Manager removes the extra directory when it extracts the archive.
> Put the bundle at the top of the archive anyway.
> That layout works with the most tools.

### Calculate the checksum

A `binaryTarget` that downloads a bundle needs the SHA-256 checksum of the archive.
Compute it with `swift package compute-checksum`:

```bash
swift package compute-checksum MyLibrary.artifactbundle.zip
```

The command prints the checksum:

```
a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
```

### Publish the archive

Upload the archive to a location that serves it over HTTPS.
This example uses the `gh` command-line tool to create a GitHub release with the archive attached:

```bash
gh release create v1.0.0 \
    --title "MyLibrary v1.0.0" \
    --notes "Initial release" \
    MyLibrary.artifactbundle.zip
```

You can also create the release and upload the archive in the GitHub web interface.

## Use the artifact bundle

Declare a binary target in `Package.swift`.
Give it the URL of the archive and the checksum you computed:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    products: [
        .library(name: "MyApp", targets: ["MyApp"])
    ],
    targets: [
        .binaryTarget(
            name: "MyLibrary",
            url: "https://github.com/yourorg/mylib/releases/download/v1.0.0/MyLibrary.artifactbundle.zip",
            checksum: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"
        ),
        .target(
            name: "MyApp",
            dependencies: ["MyLibrary"]
        ),
    ]
)
```

Import the module in Swift code:

```swift
import MyLibrary

func example() {
    let result = myLibraryFunction()
    print("Result: \(result)")
}
```

To learn more about adding binary targets as dependencies, read <doc:AddingDependencies>.

## See Also

- <doc:ArtifactBundleReference>
- <doc:ModuleMaps>
- <doc:CreatingCLanguageTargets>
