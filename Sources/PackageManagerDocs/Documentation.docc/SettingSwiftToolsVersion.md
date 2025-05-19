# Setting the Swift tools version

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

The tools version declares the minimum version of the Swift tools required to
use the package, determines what version of the PackageDescription API should
be used in the `Package.swift` manifest, and determines which Swift language
compatibility version should be used to parse the `Package.swift` manifest.

When resolving package dependencies, if the version of a dependency that would
normally be chosen specifies a Swift tools version which is greater than the
version in use, that version of the dependency will be considered ineligible
and dependency resolution will continue with evaluating the next-best version.
If no version of a dependency (which otherwise meets the version requirements
from the package dependency graph) supports the version of the Swift tools in
use, a dependency resolution error will result.

### Swift Tools Version Specification

The Swift tools version is specified by a special comment in the first line of
the `Package.swift` manifest. To specify a tools version, a `Package.swift` file
must begin with the string `// swift-tools-version:`, followed by a version
number specifier.

The version number specifier follows the syntax defined by semantic versioning
2.0, with an amendment that the patch version component is optional and
considered to be 0 if not specified. The `semver` syntax allows for an optional
pre-release version component or build version component; those components will
be completely ignored by the package manager currently.
After the version number specifier, an optional `;` character may be present;
it, and anything else after it until the end of the first line, will be ignored
by this version of the package manager, but is reserved for the use of future
versions of the package manager.

Some Examples:

    // swift-tools-version:3.1
    // swift-tools-version:3.0.2
    // swift-tools-version:4.0

### Tools Version Commands

The following Swift tools version commands are supported:

* Report tools version of the package:

        $ swift package tools-version

* Set the package's tools version to the version of the tools currently in use:

        $ swift package tools-version --set-current

* Set the tools version to a given value:

        $ swift package tools-version --set <value>

