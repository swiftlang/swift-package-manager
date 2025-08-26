# Setting the Swift tools version

Define the minimum version of the swift compiler required for your package.

## Overview

The tools version declares the minimum version of the Swift compiler required to
use the package, as well as how parse the `Package.swift` manifest.
When you create a new package using <doc:PackageInit>, the minimum version is set automatically to the current version.
The version is specified on the first line of the manifest with the comment `// swift-tools-version:` and the version for the Swift compiler.
The version is a semantic version, with the exception that a patch version is inferred to be `0` if you don't specify it.

For example, the following line asserts the package requires the Swift compiler version 6.1 or later:

```swift
// swift-tools-version:6.1
```

### Resolving dependencies with different tools versions

When resolving package dependencies, if the tools version of a dependency is greater than the version in use, that version of the dependency is ineligible and dependency resolution continues with evaluating the next-best version.

If no tools version of a dependency, which otherwise meets the package version requirements, supports the version of the Swift tools in use, the package manager presents a dependency resolution error.
For more information on providing package manifests for specific Swift versions, see <doc:SwiftVersionSpecificPackaging>.

### Adjusting the tools version.

Edit the `Package.swift` to adjust the version, or use <doc:PackageToolsVersion> to report or set the the tools version.
