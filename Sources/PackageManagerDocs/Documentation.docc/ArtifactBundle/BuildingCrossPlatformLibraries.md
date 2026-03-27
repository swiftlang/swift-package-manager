# Building cross-platform libraries

Compile static libraries with the correct build flags and compatibility settings for distribution.

## Overview

Building cross-platform libraries for artifact bundles requires careful attention to compiler flags, deployment targets, and runtime library compatibility.
Static libraries must be compiled separately for each target platform with appropriate settings to ensure your library works reliably across different operating systems and architectures.

This guide covers the build process fundamentals, platform-specific configuration, and best practices for creating portable static libraries that work across macOS, iOS, and Linux platforms.

## Understand the build process

A **static library** (`.a` file) is an archive of compiled object files.
When you link against a static library, the linker copies the relevant code directly into your executable.

The build process follows these stages:

```
Source Code (.c, .cpp, .rs)
        ↓
[Compiler (gcc, clang, rustc)]
        ↓
Object Files (.o)
        ↓
[Archiver (ar)]
        ↓
Static Library (.a)
```

Understanding this pipeline helps you control the compilation and archiving steps needed for each target platform.

## Set deployment targets for Apple platforms

Always set minimum deployment targets to match your Swift package requirements.
This ensures your library uses APIs compatible with the minimum OS versions your package supports.

### Configure macOS deployment target

Set the `MACOSX_DEPLOYMENT_TARGET` environment variable before building:

```bash
# For macOS
export MACOSX_DEPLOYMENT_TARGET=15.0

# Build with Rust
MACOSX_DEPLOYMENT_TARGET=15.0 \
cargo rustc --release \
    --target x86_64-apple-darwin \
    --crate-type=staticlib

# Build with CMake
cmake -B build-macos \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_OSX_ARCHITECTURES=x86_64
cmake --build build-macos
```

### Configure iOS deployment target

Set the `IPHONEOS_DEPLOYMENT_TARGET` for iOS libraries:

```bash
# For iOS
export IPHONEOS_DEPLOYMENT_TARGET=18.0

# Build for iOS device
cargo rustc --release \
    --target aarch64-apple-ios \
    --crate-type=staticlib
```

## Handle Linux glibc compatibility

For maximum Linux compatibility, build against an **older glibc version**.
Binaries built with newer glibc won't run on systems with older glibc.

### Use manylinux containers

**Best Practice**: Use `manylinux` containers which provide controlled glibc versions:

```bash
# Using Docker with manylinux_2_28 (glibc 2.28)
docker run --rm -v $(pwd):/workspace \
    quay.io/pypa/manylinux_2_28_x86_64 \
    /bin/bash -c "cd /workspace && make build-linux-x86"
```

**Why manylinux_2_28?**

- glibc 2.28 is compatible with most modern Linux distributions.
- Works with Ubuntu 18.04+, Debian 10+, RHEL 8+, Amazon Linux 2.
- Binaries built with glibc 2.28 run on systems with glibc 2.28 or newer.

### Choose the right glibc version

> Tip: Build against the **oldest glibc** you want to support.
> Binaries built with newer glibc will NOT run on older systems.

| glibc Version | Container | Compatible Distributions |
|---------------|-----------|--------------------------|
| 2.17 | `manylinux2014` | CentOS 7, RHEL 7, Amazon Linux 2 (minimum) |
| 2.28 | `manylinux_2_28` | Ubuntu 18.04+, Debian 10+, RHEL 8+, Amazon Linux 2 |
| 2.31 | `manylinux_2_31` | Ubuntu 20.04+, Debian 11+, RHEL 9+ |
| 2.35 | Native | Ubuntu 22.04+, Debian 12+ |

**Recommended**: Use `manylinux_2_28` for broad compatibility across enterprise and modern Linux distributions.

### Build for multiple glibc versions

If you need to support both legacy and modern systems, create separate builds:

```bash
#!/bin/bash
set -euo pipefail

# Build for glibc 2.28 (broad compatibility)
docker run --rm -v $(pwd):/work -w /work \
    quay.io/pypa/manylinux_2_28_x86_64 \
    bash -c "make build-linux-x86"

# Build for musl (Alpine/static)
docker run --rm -v $(pwd):/work -w /work \
    alpine:latest \
    sh -c "apk add --no-cache build-base rust cargo && \
           cargo build --release --target x86_64-unknown-linux-musl"
```

## Consider musl for static linking

Alpine Linux and container-focused deployments benefit from musl-based builds.

| Feature | glibc | musl |
|---------|-------|------|
| **Distribution** | Ubuntu, Debian, RHEL, CentOS | Alpine Linux |
| **Binary Size** | Larger | Smaller |
| **Static Linking** | Problematic (licensing) | Fully static |
| **Compatibility** | Industry standard | Growing adoption |
| **Use Case** | General purpose | Containers, embedded |

**When to provide musl binaries**:

- Users deploying in Alpine Linux containers
- Need for fully static binaries
- Minimal Docker images

## Use static linking for dependencies

Use static linking for dependencies to avoid runtime linking issues:

```bash
# Rust: statically link dependencies
cargo rustc --release \
    --target x86_64-unknown-linux-gnu \
    --features vendored-openssl \
    --crate-type=staticlib

# C++: static libstdc++
g++ -static-libstdc++ -static-libgcc -c mylib.cpp
```

Static linking ensures your library doesn't depend on specific versions of system libraries at runtime.

## Build with C++ and CMake

For C++ projects, CMake provides cross-platform build configuration.

### Set up CMakeLists.txt

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.20)
project(MyLibrary)

# Build static library
add_library(MyLibrary STATIC
    src/mylib.cpp
    src/helper.cpp
)

# Set C++ standard
target_compile_features(MyLibrary PUBLIC cxx_std_17)

# Platform-specific settings
if(APPLE)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")
endif()
```

### Build for each platform

```bash
# macOS x86_64
cmake -B build-macos-x86 -DCMAKE_OSX_ARCHITECTURES=x86_64
cmake --build build-macos-x86

# macOS ARM64
cmake -B build-macos-arm -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build-macos-arm

# Linux x86_64
cmake -B build-linux -DCMAKE_SYSTEM_NAME=Linux
cmake --build build-linux
```

## Build with Rust and Cargo

Rust's Cargo build system provides cross-compilation support.

### Configure Cargo.toml

```toml
# Cargo.toml
[package]
name = "mylib"
version = "1.0.0"

[lib]
crate-type = ["staticlib"]

[dependencies]
# Use vendored/static features when available
openssl = { version = "0.10", features = ["vendored"] }

[features]
xz2-static = ["xz2/static"]
```

### Build for all target platforms

```bash
#!/bin/bash
set -euo pipefail

# Install targets
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin
rustup target add x86_64-unknown-linux-gnu
rustup target add aarch64-unknown-linux-gnu

# Build for all platforms
cargo rustc --release --target x86_64-apple-darwin --crate-type=staticlib
cargo rustc --release --target aarch64-apple-darwin --crate-type=staticlib
cargo rustc --release --target x86_64-unknown-linux-gnu --crate-type=staticlib
cargo rustc --release --target aarch64-unknown-linux-gnu --crate-type=staticlib
```

### Build Linux targets in Docker

For Linux builds from macOS, use a container runtime with the appropriate container or a VM to build:

```bash
# Build for glibc 2.28
docker run --rm \
    -v $(pwd):/workspace \
    -w /workspace \
    quay.io/pypa/manylinux_2_28_x86_64 \
    bash -c "
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source \$HOME/.cargo/env
        cargo build --release --target x86_64-unknown-linux-gnu
    "
```

