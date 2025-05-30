# Packaging based on the version of Swift

Provide a package manifest for a specific version of Swift.

## Overview

The package manager supports packages that work with a variety of versions, both the versions of the language and versions of the Swift toolchain, which provides the package manager.

For language spcific version checks, use the language-specific version checks available in the source code.
However, in some circumstances this may become unmanageable, specifically when the package manifest cannot be version agnostic.
An example being when you adopt new features in the package manifest that aren't present in older versions.

The package manager supports for a mechanism to allow version-specific manifests to be used alongside a current manifest to support older versions of Swift.

### Version-specific Manifest Selection

The package manager looks for a version-specific marked manifest version when loading the particular version of a package, by searching for a manifest in the form of `Package@swift-6.swift`.
The version is a loosely specified semantic version, resolving in the following order of preference:

1. `MAJOR.MINOR.PATCH` (for example, `Package@swift-6.1.1`)
2. `MAJOR.MINOR` (for example, `Package@swift-6.1`)
3. `MAJOR` (for example, `Package@swift-6`)

Use this feature to maintain compatibility with multiple Swift project versions with a substantively different manifest file for this to be viable (for example, due to changes in the manifest API).

In case the current Swift version doesn't match any version-specific manifest, the package manager picks the manifest with the most compatible tools version.
For example, if there are three manifests:

- `Package.swift` (tools version 6.0)
- `Package@swift-5.10.swift` (tools version 5.10)
- `Package@swift-5.9.swift` (tools version 5.9)

The package manager picks `Package.swift` on Swift 6 and above, because its tools version is most compatible with future version of the package manager.
When using Swift 5.10, it picka `Package@swift-5.10.swift`.
Otherwise, when using Swift 5.9 it picks `Package@swift-5.9.swift`, and this is the minimum tools version this package may be used with.

A package may have versioned manifest files which specify newer tools versions than its unversioned `Package.swift` file.
In this scenario, the package manager uses the manifest corresponding to the newest-compatible tools version.

> Note: Support for having a versioned manifest file with a _newer_ tools version was required when the feature was first introduced, because prior versions of the package manager were not aware of the concept and only knew to look for the unversioned `Package.swift`. This is still supported, but there have been many Swift releases since the feature was introduced. It is a best practice to have `Package.swift` declare the newest-supported tools version and for versioned manifest files to only specifer older versions.

### Version-specific tags when resolving remote dependencies

The tags that define package versions can _optionally_ be suffixed with a marker in the form of `@swift-3`.
When the package manager is determining the available tags for a repository, _if_ a version-specific marker is available which matches the current tool version, then it *only* considers the versions which have the version-specific marker.
Conversely, version-specific tags are ignored by any non-matching tool version.

For example, suppose the package `PlayingCard` has the tags `1.0.0`, `1.2.0@swift-5`, and `1.3.0`.
If the package manager is from version 5.0 of the Swift toolchain and evaluates the available versions for the package, it only considers version `1.2.0`.
In the same scenario, using Swift 6 or later only attempts to resolve against versions `1.0.0` and `1.3.0`.

This feature is intended for use in the following scenarios:

1. A package wishes to maintain support for Swift 3.0 in older versions, but newer versions of the package require Swift 4.0 for the manifest to be readable.
   Since Swift 3.0 will not know to ignore those versions, it would fail when performing dependency resolution on the package if no action is taken.
   In this case, the author can re-tag the last versions which supported Swift 3.0 appropriately.

2. A package wishes to maintain dual support for Swift 3.0 and Swift 4.0 at the same version numbers, but this requires substantial differences in the code.
   In this case, the author can maintain parallel tag sets for both versions.

It is *not* expected that the packages would ever use this feature unless absolutely necessary to support existing clients.
Specifically, packages *should not* adopt this syntax for tagging versions supporting the _latest released_ Swift version.
The package manager supports looking for any of the following marked tags, in order of preference:

1. `MAJOR.MINOR.PATCH` (e.g., `1.2.0@swift-3.1.2`)
2. `MAJOR.MINOR` (e.g., `1.2.0@swift-3.1`)
3. `MAJOR` (e.g., `1.2.0@swift-3`)
