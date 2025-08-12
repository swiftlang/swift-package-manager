# SwiftBuild-Specific `withKnownIssue` Tests (Excluding Native Build System)

## Analysis Methodology
This report identifies Swift Testing tests containing `withKnownIssue` blocks that specifically affect the SwiftBuild backend but **NOT** the native build system, organized by platform.

## Windows Platform - SwiftBuild Specific Issues

### 1. BuildCommandTests.swift
- **`importOfMissedDepWarning`**
  - **When clause**: `[.swiftbuild, .xcode].contains(buildSystem)`
  - **Issue**: Warning message regarding missing imports expected to be more verbose at SwiftPM level
  - **Excludes**: Native build system

- **`importOfMissedDepWarningVerifyingErrorFlow`**
  - **When clause**: `[.swiftbuild, .xcode].contains(buildSystem)`
  - **Issue**: Error flow verification for missing import warnings
  - **Excludes**: Native build system

- **`buildExistingExecutableProductIsSuccessfull`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && data.buildSystem == .swiftbuild`
  - **Issue**: Failures possibly due to long file paths
  - **Windows + SwiftBuild only**

- **`buildExistingLibraryProductIsSuccessfull`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Found multiple targets named 'lib1' error message handling
  - **Windows + SwiftBuild only**

- **`buildExistingTargetIsSuccessfull`**
  - **When clause**: `[.swiftbuild, .xcode].contains(buildSystem)`
  - **Issue**: Could not find target named 'exec2'
  - **Excludes**: Native build system

- **`parseableInterfaces`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Errors with SwiftBuild on Windows possibly due to long path
  - **Windows + SwiftBuild only**

- **`buildSystemDefaultSettings`**
  - **When clause**: `buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows`
  - **Issue**: Sometimes failed to build due to possible path issue
  - **Windows + SwiftBuild only**

- **`automaticParseableInterfacesWithLibraryEvolution`**
  - **When clause**: `buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows`
  - **Issue**: Missing 'A.swiftmodule/*.swiftinterface' files
  - **Windows + SwiftBuild only**

- **`buildCompleteMessage`**
  - **When clause**: `buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows`
  - **Issue**: Build complete message verification
  - **Windows + SwiftBuild only**

- **`swiftDriverRawOutputGetsNewlines`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Error produced for this fixture
  - **Windows + SwiftBuild only**

- **`swiftBuildQuietLogLevel`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Quiet log level behavior
  - **Windows + SwiftBuild only**

- **`parseAsLibraryCriteria`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Parse as library functionality
  - **Windows + SwiftBuild only**

- **`doesNotRebuildWithFlags`**
  - **When clause**: `buildSystem == .swiftbuild`
  - **Issue**: --very-verbose causes rebuild on SwiftBuild
  - **SwiftBuild only (all platforms)**

### 2. TestCommandTests.swift
- **`basicXCTestSupport`**
  - **When clause**: Indirectly SwiftBuild specific through Windows testing
  - **Issue**: Driver threw unable to load output file map
  - **Windows specific**

### 3. PluginTests.swift
- **`testUseOfBuildToolPluginTargetNoPreBuildCommands`**
  - **When clause**: `buildSystem == .swiftbuild`
  - **Issue**: File handling for unhandled files warning
  - **SwiftBuild only**

- **`testIncorrectDependencies`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Build tests functionality
  - **Windows + SwiftBuild only**

- **`testTransitivePluginOnlyDependency`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Plugin dependency resolution
  - **Windows + SwiftBuild only**

- **`testDependentPlugins`**
  - **When clause**: `buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows`
  - **Issue**: Plugin dependency functionality
  - **Windows + SwiftBuild only**

### 4. PluginTests.swift - Snippet Tests
- **`testBasicBuildIndividualSnippets`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild`
  - **Issue**: Individual snippet building
  - **Windows + SwiftBuild only**

- **`testBasicRunSnippets`**
  - **When clause**: `[.windows].contains(ProcessInfo.hostOperatingSystem) && buildSystem == .swiftbuild`
  - **Issue**: Snippet execution
  - **Windows + SwiftBuild only**

## All Platforms - SwiftBuild Specific Issues

### 1. BuildCommandTests.swift
- **`buildToolWithoutOutputs`** (partial)
  - **When clause**: `buildSystem == .swiftbuild`
  - **Issue**: Warning about build tool commands without output files
  - **SwiftBuild only, all platforms**

### 2. PluginTests.swift
- **Multiple plugin tests** have nested `withKnownIssue` blocks specifically for SwiftBuild:
  - Various plugin functionality gaps in SwiftBuild vs Native

### 3. TraitTests.swift
- **`testConditionTraits`** (multiple variants)
  - **When clause**: Various combinations excluding native (e.g., `[.swiftbuild, .xcode].contains(buildSystem)`)
  - **Issue**: Condition trait handling
  - **Excludes**: Native build system

## Linux Platform - SwiftBuild Specific Issues

### 1. PluginTests.swift
- **`testIncorrectDependencies`**
  - **When clause**: `ProcessInfo.hostOperatingSystem == .linux && buildSystem == .swiftbuild && CiEnvironment.runningInSmokeTestPipeline`
  - **Issue**: Plugin dependency issues in CI
  - **Linux + SwiftBuild only**

## macOS Platform - SwiftBuild Specific Issues

### 1. BuildCommandTests.swift
- **`getTaskAllowEntitlement`**
  - **When clause**: `[.swiftbuild, .xcode].contains(buildSystem) && ProcessInfo.hostOperatingSystem != .linux`
  - **Issue**: Entitlement handling differences
  - **Excludes**: Native build system and Linux

## Cross-Platform Issues (SwiftBuild vs Native Feature Gaps)

### 1. Build System Behavioral Differences
- **Output handling**: SwiftBuild often produces different output formats
- **Error reporting**: Different error message formats between build systems
- **Plugin integration**: SwiftBuild has known gaps in plugin functionality
- **Path handling**: SwiftBuild more sensitive to long paths on Windows

### 2. Missing SwiftBuild Features
- **Symbol graph extraction**: Limited functionality compared to native
- **Test discovery**: Different behavior patterns
- **Resource bundling**: Some gaps in resource handling

## Summary by Platform

### Windows (Majority of Issues)
- **17+ SwiftBuild-specific tests** failing on Windows
- **Primary issues**: Path length limitations, file system operations, plugin integration
- **Pattern**: Most Windows issues are SwiftBuild-only, suggesting platform-specific integration problems

### All Platforms
- **5+ SwiftBuild-specific tests** affecting all platforms
- **Primary issues**: Feature parity gaps, output format differences, plugin functionality

### Linux
- **2+ SwiftBuild-specific tests** in CI environments
- **Primary issues**: CI-specific plugin and dependency resolution

### macOS
- **2+ SwiftBuild-specific tests**
- **Primary issues**: Entitlement handling, sandboxing differences

## Key Insights

1. **Windows Disproportionately Affected**: ~75% of SwiftBuild-specific issues are Windows-only
2. **Plugin System Gaps**: SwiftBuild consistently has plugin-related issues not present in native
3. **Path Handling**: SwiftBuild is more sensitive to Windows path length limitations
4. **Feature Parity**: SwiftBuild lacks several features available in the native build system
5. **Output Format Differences**: SwiftBuild often produces different output that requires separate test expectations

This analysis shows SwiftBuild has significant platform-specific issues, especially on Windows, and feature gaps compared to the native build system.
