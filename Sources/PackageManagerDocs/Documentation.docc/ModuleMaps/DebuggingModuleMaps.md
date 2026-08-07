# Debugging Module Maps

Diagnose and resolve issues when Swift can't import your C or C++ libraries.

## Overview

When you create module maps for C libraries, compilation errors or import failures indicate problems with your configuration.
This article shows you how to test module maps and fix common issues.

Use these techniques when:

- Swift can't find your module
- Headers fail to import
- C++ code produces compilation errors
- You need to verify Swift Package Manager configures your module correctly

## Test your module map

Verify that Swift can import your module before distributing it.

### Create a simple import test

Create a test Swift file that imports your module:

```swift
// test.swift
import MyLibrary

print("Module imported successfully")
```

Build the test file:

```bash
swiftc -I path/to/module/directory test.swift
```

If the module map has errors, the compiler produces diagnostic messages that indicates what's wrong.

### Verify build configuration

Use verbose output to verify Swift Package Manager configures your module correctly:

```bash
swift build --verbose
```

Look for these compiler flags in the output:

- `-I` flags pointing to your header directories
- `-fmodule-map-file=` flags pointing to your module map
- Link flags for binary libraries

## Resolve common issues

When Swift can't find your module or headers, check these common causes.

### Fix module name mismatches

Verify the module name in the module map matches the artifact or target name.

If Swift can't find your module, verify:

- The module name in the module map matches the artifact or target name exactly.
- The module map file is named `module.modulemap`.
- The `moduleMapPath` in info.json points to the correct file.
- For system libraries, the target directory contains the module map.

### Locate missing headers

Verify header paths and file locations when the compiler reports missing headers.

If the compiler reports a missing header:

- Check that the header path in the module map is relative to the module map file.
- Verify the header file exists at the specified location.
- Ensure the `headerPaths` array in info.json includes the directory.

### Fix C++ compilation errors

Add C++ language support directives to resolve C++ syntax errors.

If you get errors about C++ syntax:

- Add `requires cplusplus` to your module map.
- For C++11 or later features, use `requires cplusplus11`.
- Verify your headers use appropriate `#ifdef __cplusplus` guards for mixed C/C++ code.
