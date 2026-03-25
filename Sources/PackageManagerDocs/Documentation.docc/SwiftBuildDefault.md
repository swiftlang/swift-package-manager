# [6.4] Swift Build System now the default in SwiftPM

Understand and use the new build system for Package Manager.

@Metadata {
    @Available("Swift", introduced: "6.4")
}

## Overview

Swift Package Manager introduced [Swift Build](https://github.com/swiftlang/swift-build) as a preview replacement for its native build system in Swift 6.3 and adopted it as the default build system in Swift 6.4.  This document outlines the key differences and known issues.

We encourage you to [use](#How-to-use-the-Swift-Build-build-system) the build system in your project and [report any issues](#Reporting-issues) you encounter.

For more information about the migration to Swift Build, see [Evolving SwiftPM buildswith Swift Build](https://forums.swift.org/t/evolving-swiftpm-builds-with-swift-build/77596) on the [Swift Forums](https://forums.swift.org).

## Migration plan

The Swift Build integration follows these phases:

1. **Preview Phase** - Testing and feedback collection (Swift 6.3)
2. **Feature Parity** - Address remaining gaps and platform issues
3. **Default Migration** - Transition to Swift Build as default (Swift 6.4 - Current)
4. **Legacy Build System Removal** - Remove `native` and `xcode` build systems in a future release

## How to use the Swift Build build system

As of Swift 6.4, Swift Build is the default build system and no additional flags are required:

```bash
swift build
swift test
swift run
```

### Using Swift Build in Swift 6.3

In Swift 6.3 (preview phase), you need to explicitly opt-in using the `--build-system swiftbuild` flag:

```bash
swift build --build-system swiftbuild
swift test --build-system swiftbuild
swift run --build-system swiftbuild
```

## Key improvements and differences between Native build system

- Build artifacts are output to a different location.  For all build systems, using the `swift build --show-bin-path <other build arguments>` is the recommended way to determine the build output location.
- **`--static-swift-stdlib`**: Stricter validation (errors instead of silently ignoring)
  - The native build system silently ignored this option on some platforms; Swift Build now produces an error.
  - The Swift Build build system will generate an error on platforms where static libraries are not supported.
- Swift Build does not support test targets depending on other test targets.  To work around this,
  create a non-test target for the test target to depend on.  A runtime error (sample below) will occur if this target is added as a
  dependency on non-test targets.
    ```
    dyld[67034]: Library not loaded: @rpath/libTesting.dylib
    Referenced from: <30F1D85A-75C7-358C-B169-96E34550501C> /Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/swift-package
    Reason: tried: '/usr/lib/swift/libTesting.dylib' (no such file, not in dyld cache), '/System/Volumes/Preboot/Cryptexes/OS/usr/lib/swift/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/usr/lib/swift/libTesting.dylib' (no such file, not in dyld cache), '/System/Volumes/Preboot/Cryptexes/OS/usr/lib/swift/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/libTesting.dylib' (no such file), '/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/git/swiftlang/swift-package-manager-3/.build/out/Products/Debug/PackageFrameworks/libTesting.dylib' (no such file), '/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Users/jappleseed/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-04-01-a.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file), '/System/Volumes/Preboot/Cryptexes/OS/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx/libTesting.dylib' (no such file)
    ```
- Swift Build tasks planned by build tool plugins no longer have unrestricted access to environment variables in order
  to avoid excessive invalidation in incremental builds.


### Detailed differences

#### Resource support parity with xcodebuild
- When targeting Apple platforms, SwiftPM, the same set of resource rules as that `xcodebuild` followsare consistently applied when a package contains resource types like asset catalogs, storyboards, Metal sources, etc.

#### Swift Driver integration
- The `--use-integrated-swift-driver` command-line option is deprecated and has not effect. Swift Build always uses the library-based Swift driver.
- On supported platforms, SwiftPM will make use of explicitly-built Clang and Swift modules.

#### Enhanced diagnostics
- Logging and diagnostic differences between native and Swift Build build systems

#### Other

- Supports building universal binaries when targeting Apple platforms. Example invocation: `swift build --arch arm64 --arch x86_64`

## Known issues

- Swift Build fails to build projects with Linux SDKs generated _by_ the SDK generator.
  - **Tracking**: [package-manager#10006](https://github.com/swiftlang/swift-package-manager/issues/10006)

- Using the `--explicit-target-dependency-import-check` command line option does not behave as expected when building with Swift Build
  - **Tracking**: [swiftlang/swift-package-manager#9620](https://github.com/swiftlang/swift-package-manager/issues/9620)
  - build settings are set in the SwiftPM PIF builder

- Swift Build does not support overlapping executable product names and library product names (case-insensitive).
  - **Tracking**: [swiftlang/swift-package-manager#9184](https://github.com/swiftlang/swift-package-manager/issues/9184)

- `swift sdk configure` recently updated for the Native.  The functionality is being migrated to Swift Build.
   - Submitted recently for native build system under [swiftlang/swift-package-manager#p229](https://github.com/swiftlang/swift-package-manager/pull/9229)
   - **Tracking**: [swift-package-manager#10012](https://github.com/swiftlang/swift-package-manager/issues/10012)

## Troubleshooting

If your package fails to build with Swift Build in Swift 6.4, you can fall back to the previous native build system using the `--build-system native` flag:

```bash
swift build --build-system native
swift test --build-system native
swift run --build-system native
```

If you build passes using the Native build system, but fails using Swift Build, please [report the issue](#Reporting-issues).

## Reporting issues

Please follow these steps when reporting issues:

1. Review the [known issues](#Known-issues) listed above to ensure your issue has not already been identified.
2. If your issue is not listed, [submit a new issue](https://github.com/swiftlang/swift-package-manager/issues) on GitHub.
3. Include the following information in your report:
   - The exact command that failed
   - Complete error output
   - System information (operating system, Swift version, etc.)
   - Whether the same command works with the native build system
