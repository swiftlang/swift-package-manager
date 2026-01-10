# Wrapping CMake-based C/C++ Libraries with Swift Package Manager

This guide shows you how to create a Swift Package that wraps a CMake-based C/C++ library (as a git submodule) with ergonomic Swift APIs.

## Table of Contents

* [Quick Start](#quick-start)
* [Step-by-Step Tutorial](#step-by-step-tutorial)
* [Configuration Reference](#configuration-reference)
* [Module Map Modes](#module-map-modes)
* [Advanced Topics](#advanced-topics)
  * [Cross-Compilation and Swift SDKs](#cross-compilation-and-swift-sdks)
  * [Textual Headers](#textual-headers)
  * [Build Caching](#build-caching)
* [Troubleshooting](#troubleshooting)
* [Examples](#examples)

## Quick Start

```bash
# 1. Create your Swift package
mkdir MyAwesomeWrapper && cd MyAwesomeWrapper
swift package init --type library

# 2. Add the C/C++ library as a submodule
git init
git submodule add https://github.com/vendor/awesome-lib ThirdParty/AwesomeLib

# 3. Check CMake prerequisites
swift package diagnose-cmake

# 4. Analyze the library and generate configuration
swift package analyze-cmake ThirdParty/AwesomeLib \
    --module-name CAwesomeLib \
    --write

# 5. Update Package.swift to include the system library target
# 6. Create Swift wrapper code
# 7. Build!
swift build
```

## Step-by-Step Tutorial

### Example: Wrapping SDL3

We'll walk through wrapping SDL3 (Simple DirectMedia Layer) as a complete example.

#### Step 1: Create Your Package

```bash
mkdir MySDL
cd MySDL
swift package init --type library
git init
```

#### Step 2: Add SDL as a Submodule

```bash
git submodule add https://github.com/libsdl-org/SDL.git ThirdParty/SDL
git commit -m "Add SDL submodule"
```

**Why a submodule?** This keeps the C/C++ library separate, tracked at a specific version, and makes updates explicit.

#### Step 3: Verify CMake Is Available

```bash
swift package diagnose-cmake
```

Expected output:
```
CMake Diagnostics
=================

cmake: /usr/local/bin/cmake
  version: 3.28.0

ninja: /usr/local/bin/ninja
  version: 1.11.1

PATH directories:
  - /usr/local/bin
  - /usr/bin
  ...
```

If CMake is missing, install it:
- **macOS**: `brew install cmake`
- **Ubuntu**: `sudo apt-get install cmake`
- **Windows**: `winget install cmake`

#### Step 4: Analyze and Configure

```bash
swift package analyze-cmake ThirdParty/SDL \
    --module-name CSDL \
    --write
```

This command:
1. Scans headers in `ThirdParty/SDL/include/`
2. Identifies textual headers (e.g., `begin_code.h`/`close_code.h`)
3. Detects headers requiring external dependencies (e.g., OpenGL, Vulkan)
4. Generates suggested configuration files

**Output:** Two files are created:
- `ThirdParty/SDL/.spm-cmake.json` - CMake build configuration
- `ThirdParty/SDL/config/CSDL.modulemap` - Clang module map

#### Step 5: Review and Customize Configuration

**`.spm-cmake.json`** - Configure the CMake build:

```json
{
  "defines": {
    "SDL_SHARED": "OFF",
    "SDL_STATIC": "ON",
    "SDL_TESTS": "OFF"
  },
  "moduleMap": {
    "mode": "provided",
    "path": "config/CSDL.modulemap",
    "installAt": "include/module.modulemap"
  }
}
```

**`config/CSDL.modulemap`** - Define how Swift sees the C headers:

```c
module CSDL [system] {
  umbrella "SDL3"

  // Textual headers - included via #include, not compiled into module
  textual header "SDL3/SDL_begin_code.h"
  textual header "SDL3/SDL_close_code.h"

  // Exclude headers requiring external dependencies
  exclude header "SDL3/SDL_main.h"
  exclude header "SDL3/SDL_egl.h"
  exclude header "SDL3/SDL_vulkan.h"
  exclude header "SDL3/SDL_opengl.h"

  export *
  module * { export * }

  link "SDL3"
}
```

#### Step 6: Update Package.swift

Add the system library target and your Swift wrapper:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MySDL",
    products: [
        .library(name: "MySDL", targets: ["MySDL"])
    ],
    targets: [
        // System library target - SwiftPM will build this via CMake
        .systemLibrary(
            name: "CSDL",
            path: "ThirdParty/SDL"
        ),

        // Swift wrapper with ergonomic APIs
        .target(
            name: "MySDL",
            dependencies: ["CSDL"]
        ),

        .testTarget(
            name: "MySDLTests",
            dependencies: ["MySDL"]
        )
    ]
)
```

#### Step 7: Create Swift Wrapper

**Sources/MySDL/MySDL.swift**:

```swift
import CSDL

/// Swift wrapper for SDL3 with ergonomic APIs
public struct SDL {

    /// Get SDL version as a string
    public static var version: String {
        let v = SDL_GetVersion()
        let major = (v >> 24) & 0xFF
        let minor = (v >> 16) & 0xFF
        let patch = v & 0xFFFF
        return "\(major).\(minor).\(patch)"
    }

    /// Initialize SDL subsystems
    public static func initialize(_ subsystems: Subsystem) throws {
        guard SDL_Init(subsystems.rawValue) == 0 else {
            throw SDLError.initializationFailed
        }
    }

    /// Quit SDL
    public static func quit() {
        SDL_Quit()
    }
}

// MARK: - Type-safe wrappers

extension SDL {
    public struct Subsystem: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let video = Subsystem(rawValue: UInt32(SDL_INIT_VIDEO))
        public static let audio = Subsystem(rawValue: UInt32(SDL_INIT_AUDIO))
        public static let gamepad = Subsystem(rawValue: UInt32(SDL_INIT_GAMEPAD))
    }
}

// MARK: - Error handling

public enum SDLError: Error {
    case initializationFailed

    public var localizedDescription: String {
        "SDL initialization failed"
    }
}
```

#### Step 8: Add Tests

**Tests/MySDLTests/MySDLTests.swift**:

```swift
import XCTest
@testable import MySDL
import CSDL

final class MySDLTests: XCTestCase {

    func testVersion() throws {
        let version = SDL.version
        XCTAssertFalse(version.isEmpty)
        print("SDL Version: \(version)")
    }

    func testInitQuit() throws {
        try SDL.initialize(.video)
        SDL.quit()
    }
}
```

#### Step 9: Build and Test

```bash
swift build
swift test
```

**What happens during build:**

1. SwiftPM detects `CMakeLists.txt` in `ThirdParty/SDL/`
2. Reads `.spm-cmake.json` for configuration
3. Runs CMake to configure, build, and install SDL3:
   ```bash
   cmake -S ThirdParty/SDL -B .build/cmake/.../build \
         -DCMAKE_BUILD_TYPE=Debug \
         -DCMAKE_INSTALL_PREFIX=.build/cmake/.../staging \
         -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF
   cmake --build .build/cmake/.../build
   cmake --install .build/cmake/.../build
   ```
4. Copies the module map to staging area
5. Discovers libraries (`libSDL3.a`)
6. Compiles Swift code linking against SDL3

## Configuration Reference

### .spm-cmake.json

Complete schema:

```json
{
  "defines": {
    "<CMAKE_VAR>": "<value>",
    "BUILD_SHARED_LIBS": "OFF",
    "ENABLE_TESTING": "OFF"
  },
  "env": {
    "CC": "/path/to/clang",
    "CXX": "/path/to/clang++",
    "AR": "/path/to/llvm-ar"
  },
  "moduleMap": {
    "mode": "auto | provided | overlay | none",
    "path": "config/MyModule.modulemap",
    "installAt": "include/module.modulemap",
    "textualHeaders": [
      "include/prefix.h",
      "include/suffix.h"
    ],
    "excludeHeaders": [
      "include/platform_specific.h",
      "include/requires_external_lib.h"
    ]
  }
}
```

#### CMake Defines

Any CMake cache variables can be set via `defines`:

```json
{
  "defines": {
    "BUILD_SHARED_LIBS": "OFF",      // Static linking
    "CMAKE_BUILD_TYPE": "Release",   // Override build type
    "ENABLE_FEATURE_X": "ON",        // Enable library feature
    "USE_SYSTEM_LIBS": "OFF"         // Don't use system libs
  }
}
```

#### Environment Variables

The `env` field allows you to set environment variables for the CMake build process:

```json
{
  "env": {
    "CC": "/usr/local/bin/clang-18",
    "CXX": "/usr/local/bin/clang++-18",
    "AR": "/usr/local/bin/llvm-ar",
    "RANLIB": "/usr/local/bin/llvm-ranlib",
    "STRIP": "/usr/local/bin/llvm-strip"
  }
}
```

This is useful for:
- Specifying custom compiler toolchains
- Setting Android NDK paths
- Overriding default build tools
- Platform-specific tool selection

Note: User-provided `env` takes precedence over toolchain defaults.

#### Module Map Configuration

| Field | Description |
|-------|-------------|
| `mode` | How to generate the module map (see [Module Map Modes](#module-map-modes)) |
| `path` | Path to provided module map (relative to library root) |
| `installAt` | Where to install the module map in staging area |
| `textualHeaders` | Headers to include textually (not compiled into module) |
| `excludeHeaders` | Headers to exclude from the module |

## Module Map Modes

### Auto Mode

SwiftPM generates a module map automatically from staged headers.

```json
{
  "moduleMap": {
    "mode": "auto",
    "textualHeaders": ["include/begin.h", "include/end.h"],
    "excludeHeaders": ["include/platform.h"]
  }
}
```

**When to use:** Simple libraries with standard header structure.

### Provided Mode

You provide a custom module map.

```json
{
  "moduleMap": {
    "mode": "provided",
    "path": "config/MyModule.modulemap",
    "installAt": "include/module.modulemap"
  }
}
```

**When to use:** Complex libraries needing fine-grained control (like SDL3).

### Overlay Mode

Use VFS overlays and custom module maps.

```json
{
  "moduleMap": {
    "mode": "overlay",
    "overlay": {
      "vfs": "config/overlay.yaml",
      "moduleMapFile": "config/MyModule.modulemap"
    }
  }
}
```

**When to use:** Libraries with unconventional header layouts.

### None Mode

No automatic module map handling - you provide all flags manually.

```json
{
  "moduleMap": {
    "mode": "none"
  }
}
```

**When to use:** Complete manual control needed.

## Advanced Topics

### Textual Headers

Some libraries use "bracketing headers" that define/undefine macros around other headers:

```c
// begin_code.h
#define EXPORT __attribute__((visibility("default")))

// actual header
#include "begin_code.h"
EXPORT void my_function();
#include "end_code.h"

// end_code.h
#undef EXPORT
```

These must be marked as `textual header` in the module map:

```c
module MyLib [system] {
  umbrella "include"
  textual header "include/begin_code.h"
  textual header "include/end_code.h"
  export *
}
```

### Cross-Compilation and Swift SDKs

SwiftPM's CMake integration automatically respects your selected Swift toolchain and SDK. CMake builds align with the Swift compilation target without manual configuration.

#### Using Swift SDKs

Swift SDKs allow you to target different platforms (iOS, Android, static Linux, etc.). The CMake integration automatically configures the build for the selected SDK.

**Install and use a Swift SDK:**

```bash
# Install an SDK bundle
swift sdk install https://download.swift.org/.../swift-android.artifactbundle.tar.gz

# List available SDKs
swift sdk list

# Build with a specific SDK
swift build --swift-sdk android-armv7
```

When building with `--swift-sdk`, the CMake integration automatically sets:
- `CMAKE_SYSTEM_NAME` (Android, iOS, Linux, etc.)
- `CMAKE_ANDROID_NDK`, `CMAKE_ANDROID_ARCH_ABI`, `CMAKE_ANDROID_API` (for Android)
- `CMAKE_OSX_SYSROOT`, `CMAKE_OSX_ARCHITECTURES` (for Apple platforms)
- `CMAKE_SYSROOT`, `CMAKE_FIND_ROOT_PATH` (for cross-compilation)
- `CMAKE_C_COMPILER_TARGET`, `CMAKE_CXX_COMPILER_TARGET` (target triple)

**Example: Building for Android**

```bash
swift sdk install swift-6.0-android.artifactbundle.tar.gz
swift build --swift-sdk android-aarch64
```

CMake automatically receives:
```
CMAKE_SYSTEM_NAME=Android
CMAKE_ANDROID_ARCH_ABI=arm64-v8a
CMAKE_ANDROID_API=21
CMAKE_C_COMPILER_TARGET=aarch64-unknown-linux-android
```

#### Using Custom Toolchains (macOS)

On macOS, you can select custom Swift toolchains using the `TOOLCHAINS` environment variable. The CMake integration inherits this and uses the toolchain's compilers.

```bash
# Select a nightly toolchain
export TOOLCHAINS=org.swift.DEVELOPMENT-SNAPSHOT-2025-10-30-a

# Verify the toolchain
swift --version

# Build - CMake will use the toolchain's clang/clang++
swift build
```

The selected toolchain's compilers are automatically passed to CMake via `CC` and `CXX` environment variables.

#### Using Destination and Toolset Files

For custom cross-compilation setups, use destination or toolset JSON files:

**Destination file (linux-cross.json):**
```json
{
  "version": 1,
  "target": "aarch64-unknown-linux-gnu",
  "sysroot": "/path/to/aarch64-sysroot"
}
```

**Build with destination:**
```bash
swift build --destination linux-cross.json
```

The CMake integration reads the triple and sysroot from the destination file and configures CMake accordingly.

**Toolset file (custom-llvm.json):**
```json
{
  "version": 1,
  "compilers": {
    "C": "/opt/llvm-18/bin/clang",
    "CXX": "/opt/llvm-18/bin/clang++"
  }
}
```

**Build with toolset:**
```bash
swift build --toolset custom-llvm.json
```

#### Per-Triple Configuration

You can provide platform-specific CMake configuration by creating per-triple JSON files. This is useful when different platforms need different build settings.

**Directory structure:**
```
ThirdParty/MyLib/
  .spm-cmake.json                    # Default configuration
  .spm-cmake/
    arm64-apple-ios.json              # iOS-specific
    aarch64-unknown-linux-gnu.json    # Linux ARM64-specific
    x86_64-apple-macosx.json          # macOS x86_64-specific
```

**Example: iOS-specific configuration (.spm-cmake/arm64-apple-ios.json):**
```json
{
  "defines": {
    "BUILD_SHARED_LIBS": "OFF",
    "USE_METAL": "ON",
    "USE_OPENGL": "OFF"
  },
  "env": {
    "CC": "/path/to/ios-clang",
    "CXX": "/path/to/ios-clang++"
  }
}
```

**Configuration selection order:**
1. `.spm-cmake/<target-triple>.json` (most specific)
2. `.spm-cmake.json` (fallback)
3. Auto-detection (if no config found)

When you build with `swift build --swift-sdk ios-arm64`, SwiftPM looks for `.spm-cmake/arm64-apple-ios.json` first.

#### Environment Variable Overrides

The `env` field in `.spm-cmake.json` allows you to override environment variables for the CMake build:

```json
{
  "env": {
    "CC": "/usr/local/bin/clang-18",
    "CXX": "/usr/local/bin/clang++-18",
    "AR": "/usr/local/bin/llvm-ar",
    "RANLIB": "/usr/local/bin/llvm-ranlib",
    "STRIP": "/usr/local/bin/llvm-strip"
  }
}
```

**Precedence (highest to lowest):**
1. User-provided `env` in `.spm-cmake.json`
2. Toolchain compilers (from `TOOLCHAINS` or `--toolset`)
3. System defaults

#### Platform-Specific CMake Variables

The CMake integration automatically sets platform-specific variables based on the target triple:

**Apple platforms (iOS, tvOS, watchOS, visionOS, macOS):**
- `CMAKE_SYSTEM_NAME`: iOS, tvOS, watchOS, visionOS, or Darwin
- `CMAKE_OSX_SYSROOT`: iphoneos, iphonesimulator, appletvos, etc.
- `CMAKE_OSX_ARCHITECTURES`: arm64, x86_64, etc.
- `CMAKE_INSTALL_RPATH`: @rpath

**Linux:**
- `CMAKE_SYSTEM_NAME`: Linux
- `CMAKE_SYSROOT`: SDK sysroot path
- `CMAKE_FIND_ROOT_PATH`: SDK sysroot path
- `CMAKE_C_COMPILER_TARGET`: target triple
- `CMAKE_CXX_COMPILER_TARGET`: target triple

**Android:**
- `CMAKE_SYSTEM_NAME`: Android
- `CMAKE_ANDROID_NDK`: NDK path from environment
- `CMAKE_ANDROID_ARCH_ABI`: arm64-v8a, armeabi-v7a, x86_64, or x86
- `CMAKE_ANDROID_API`: 21 (default)
- `CMAKE_C_COMPILER_TARGET`: target triple
- `CMAKE_CXX_COMPILER_TARGET`: target triple

**Windows:**
- `CMAKE_SYSTEM_NAME`: Windows
- `CMAKE_MSVC_RUNTIME_LIBRARY`: MultiThreadedDLL (for MSVC)

**WebAssembly (WASI):**
- `CMAKE_SYSTEM_NAME`: WASI
- `CMAKE_SYSROOT`: SDK sysroot path

You can override any of these by adding them to the `defines` field in `.spm-cmake.json`.

### Build Caching

SwiftPM caches CMake builds and only rebuilds when:
- `CMakeLists.txt` changes
- `.spm-cmake.json` changes
- CMake version changes

Clean cache: `rm -rf .build/cmake/`

## Troubleshooting

### "cmake not found"

**Solution:** Install CMake
```bash
# macOS
brew install cmake

# Ubuntu/Debian
sudo apt-get install cmake

# Windows
winget install cmake
```

### "Header 'X.h' not found"

**Cause:** Header requires external dependency or is platform-specific.

**Solution:** Add to `excludeHeaders`:

```json
{
  "moduleMap": {
    "excludeHeaders": ["include/problematic.h"]
  }
}
```

### "begin_code.h included without matching end_code.h"

**Cause:** Bracketing headers being compiled into module.

**Solution:** Mark as textual:

```json
{
  "moduleMap": {
    "textualHeaders": [
      "include/begin_code.h",
      "include/end_code.h"
    ]
  }
}
```

### CMake configuration fails

**Debug:** Check CMake output:
```bash
swift build -v 2>&1 | grep cmake
```

Common issues:
- Missing dependencies
- Incompatible CMake version
- Wrong defines

### Module not found in Swift code

**Check:**
1. System library target exists in Package.swift
2. Module map is valid (run `analyze-cmake`)
3. Build succeeded (check `.build/cmake/.../staging/include/`)

## Examples

### Example 1: Simple C Library (zlib)

```json
// ThirdParty/zlib/.spm-cmake.json
{
  "defines": {
    "BUILD_SHARED_LIBS": "OFF"
  },
  "moduleMap": {
    "mode": "auto"
  }
}
```

```swift
// Package.swift
.systemLibrary(name: "CZlib", path: "ThirdParty/zlib"),
.target(name: "MyZlib", dependencies: ["CZlib"])
```

### Example 2: Complex C++ Library with External Dependencies

```json
// ThirdParty/opencv/.spm-cmake.json
{
  "defines": {
    "BUILD_SHARED_LIBS": "OFF",
    "BUILD_EXAMPLES": "OFF",
    "BUILD_TESTS": "OFF",
    "WITH_CUDA": "OFF",
    "WITH_OPENCL": "OFF"
  },
  "moduleMap": {
    "mode": "provided",
    "path": "config/OpenCV.modulemap",
    "excludeHeaders": [
      "opencv2/cuda*.hpp",
      "opencv2/opencl*.hpp"
    ]
  }
}
```

## Best Practices

1. **Pin submodule versions**: Always commit a specific commit hash
   ```bash
   cd ThirdParty/SDL
   git checkout release-3.1.0
   cd ../..
   git add ThirdParty/SDL
   git commit -m "Pin SDL to 3.1.0"
   ```

2. **Start with `analyze-cmake`**: Let the tool suggest configuration

3. **Test incrementally**: Build after each configuration change

4. **Document requirements**: Note required CMake version, system dependencies

5. **Provide Swift-friendly APIs**: Don't expose raw C pointers

6. **Add safety**: Use Swift error handling, not raw return codes

## Additional Resources

- [Swift Package Manager Documentation](README.md)
- [Package Manifest Specification](PackageDescription.md)
- [CMake Documentation](https://cmake.org/documentation/)
- [Clang Module Maps](https://clang.llvm.org/docs/Modules.html)

---

**Questions or Issues?** Check `swift package diagnose-cmake` and `swift package analyze-cmake --help`
