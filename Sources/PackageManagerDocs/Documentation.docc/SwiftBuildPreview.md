# [6.3] Preview the Swift Build System Integration

Understand, use, and preview the next-generation build system for Package Manager.

@Metadata {
    @Available("Swift", introduced: "6.3")
}

## Overview

Swift Package Manager is previewing a new build system [Swift Build](https://github.com/swiftlang/swift-build) as a replacement for the current native build system. This document outlines the current state of the preview, key differences, and known issues.


We encourage you to [try](#How-to-use-the-Swift-Build-build-system) the new build system in your project and [report any issues](#Reporting-issues) you encounter.

For more information about the migration to Swift Build, see [this forum post](https://forums.swift.org/t/evolving-swiftpm-builds-with-swift-build/77596).

## Migration plan

The Swift Build integration follows these phases:

1. **Preview Phase** (Current) - Testing and feedback collection
2. **Feature Parity** - Address remaining gaps and platform issues
3. **Default Migration** - Transition to Swift Build as default
4. **Legacy Build System Deprecation** - Phase out `native` and `xcode` build systems

## How to use the Swift Build build system

To participate in the preview, run your Swift Package Manager commands with the `--build-system swiftbuild` flag:

```bash
swift build --build-system swiftbuild
swift test --build-system swiftbuild
swift run --build-system swiftbuild
```

## Key improvements and differences


- **`--static-swift-stdlib`**: Stricter validation (errors instead of silently ignoring)
  - The native build system silently ignored this option on some platforms; Swift Build now produces an error.
  - The Swift Build build system will generate an error on Windows until static libraries are supported. See [Upcoming changes to Windows Swift SDKs](https://forums.swift.org/t/upcoming-changes-to-windows-swift-sdks/81313).

### Detailed differences

#### Resource support parity with xcodebuild
- When targeting Apple platforms using `--build-system swiftbuild`, SwiftPM now consistently applies the same set of resource rules as xcodebuild when a package contains resource types like asset catalogs, storyboards, Metal sources, etc.

#### Swift Driver integration
- The `--use-integrated-swift-driver` command-line option is considered deprecated. `--build-system swiftbuild` always uses the library-based Swift driver.
- On supported platforms, `--build-system swiftbuild` will make use of explicitly-built Clang and Swift modules.

#### Enhanced diagnostics
- Logging and diagnostic differences between native and Swift Build build systems

#### Other

- When targeting Apple platforms, `--build-system swiftbuild` supports building universal binaries. Example invocation: `swift build --build-system swiftbuild --arch arm64 --arch x86_64`

## Known issues


### Windows platform
- Swift Build does not support CodeView debug information format.
  - **Tracking**: [swiftlang/swift-package-manager#9302](https://github.com/swiftlang/swift-package-manager/issues/9302)
  - **Impact**: Limited debugging capabilities on Windows.

### Linux platform
- Coverage reporting issues on some Linux platforms
  - **Tracking**: [swiftlang/swift-package-manager#9600](https://github.com/swiftlang/swift-package-manager/issues/9600)

### Feature gaps

- The `swift run --repl` command may fail to import some modules.
  - **Tracking**: [swiftlang/swift-package-manager#8846](https://github.com/swiftlang/swift-package-manager/issues/8846)

- Swift Build does not provide sanitizer support for `scudo` and `fuzzer`.
  - **Tracking**: [swiftlang/swift-package-manager#9448](https://github.com/swiftlang/swift-package-manager/issues/9448)
  - **Impact**: Limited testing and debugging capabilities.

- Swift Build does not support the `--enable-parseable-module-interfaces` option.
  - **Tracking**: [swiftlang/swift-package-manager#9324](https://github.com/swiftlang/swift-package-manager/issues/9324)

- Test execution with coverage may fail on certain platforms.
  - **Tracking**: [swiftlang/swift-package-manager#9588](https://github.com/swiftlang/swift-package-manager/issues/9588)

- Swift SDK's and toolset.json files aren't working for the most part. The webassembly SDK is ready to use.
  - **Tracking**: [swiftlang/swift-package-manager#9346](https://github.com/swiftlang/swift-package-manager/issues/9346)

- Swift Build does not support test targets depending on other test targets.
  - **Workaround**: Create a non-test target for the test target to depend on.
  - **Tracking**: [swiftlang/swift-package-manager#9458](https://github.com/swiftlang/swift-package-manager/issues/9458)

- Expected `native` build failure in `release` configuration may not fail with Swift Build
  - **Tracking**: [swiftlang/swift-package-manager#8984](https://github.com/swiftlang/swift-package-manager/issues/8984)

- Swift Build does not support the `--explicit-target-dependency-import-check` flag.
  - **Tracking**: [swiftlang/swift-package-manager#9620](https://github.com/swiftlang/swift-package-manager/issues/9620)

- Swift Build does not pass environment variables to plugin tools.
  - **Tracking**: [swiftlang/swift-package-manager#9122](https://github.com/swiftlang/swift-package-manager/issues/9122)

- Swift Build does not support overlapping executable product names and library product names (case-insensitive).
  - **Tracking**: [swiftlang/swift-package-manager#9184](https://github.com/swiftlang/swift-package-manager/issues/9184)

## Reporting issues

Please follow these steps when reporting issues:

1. Review the [known issues](#Known-issues) listed above to ensure your issue has not already been identified.
2. If your issue is not listed, [submit a new issue](https://github.com/swiftlang/swift-package-manager/issues) on GitHub.
3. Include the following information in your report:
   - The exact command that failed
   - Complete error output
   - System information (operating system, Swift version, etc.)
   - Whether the same command works with the native build system

