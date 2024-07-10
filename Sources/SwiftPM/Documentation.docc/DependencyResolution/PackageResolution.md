# Understand Package Resolution

## Resolving Versions (Package.resolved File)

The package manager records the result of dependency resolution in a
`Package.resolved` file in the top-level of the package, and when this file is
already present in the top-level, it is used when performing dependency
resolution, rather than the package manager finding the latest eligible version
of each package. Running `swift package update` updates all dependencies to the
latest eligible versions and updates the `Package.resolved` file accordingly.

Resolved versions will always be recorded by the package manager. Some users may
choose to add the Package.resolved file to their package's .gitignore file. When
this file is checked in, it allows a team to coordinate on what versions of the
dependencies they should use. If this file is gitignored, each user will
separately choose when to get new versions based on when they run the `swift
package update` command, and new users will start with the latest eligible
version of each dependency. Either way, for a package which is a dependency of
other packages (e.g., a library package), that package's `Package.resolved` file
will not have any effect on its client packages.

The `swift package resolve` command resolves the dependencies, taking into
account the current version restrictions in the `Package.swift` manifest and
`Package.resolved` resolved versions file, and issuing an error if the graph
cannot be resolved. For packages which have previously resolved versions
recorded in the `Package.resolved` file, the resolve command will resolve to
those versions as long as they are still eligible. If the resolved version's file
changes (e.g., because a teammate pushed a new version of the file) the next
resolve command will update packages to match that file. After a successful
resolve command, the checked out versions of all dependencies and the versions
recorded in the resolved versions file will match. In most cases the resolve
command will perform no changes unless the `Package.swift` manifest or
`Package.resolved` file have changed.

Most SwiftPM commands will implicitly invoke the `swift package resolve`
functionality before running, and will cancel with an error if dependencies
cannot be resolved.

## Handling Version-specific Logic

The package manager is designed to support packages which work with a variety of
Swift project versions, including both the language and the package manager
version.

In most cases, if you want to support multiple Swift versions in a package you
should do so by using the language-specific version checks available in the
source code itself. However, in some circumstances this may become unmanageable,
specifically, when the package manifest itself cannot be written to be Swift
version agnostic (for example, because it optionally adopts new package manager
features not present in older versions).

The package manager has support for a mechanism to allow Swift version-specific
customizations for the both package manifest and the package versions which will
be considered.

### Version-specific Tag Selection

The tags which define the versions of the package available for clients to use
can _optionally_ be suffixed with a marker in the form of `@swift-3`. When the
package manager is determining the available tags for a repository, _if_
a version-specific marker is available which matches the current tool version,
then it will *only* consider the versions which have the version-specific
marker. Conversely, version-specific tags will be ignored by any non-matching
tool version.

For example, suppose the package `Foo` has the tags `[1.0.0, 1.2.0@swift-3,
1.3.0]`. If version 3.0 of the package manager is evaluating the available
versions for this repository, it will only ever consider version `1.2.0`.
However, version 4.0 would consider only `1.0.0` and `1.3.0`.

This feature is intended for use in the following scenarios:

1. A package wishes to maintain support for Swift 3.0 in older versions, but
   newer versions of the package require Swift 4.0 for the manifest to be
   readable. Since Swift 3.0 will not know to ignore those versions, it would
   fail when performing dependency resolution on the package if no action is
   taken. In this case, the author can re-tag the last versions which supported
   Swift 3.0 appropriately.

2. A package wishes to maintain dual support for Swift 3.0 and Swift 4.0 at the
   same version numbers, but this requires substantial differences in the code.
   In this case, the author can maintain parallel tag sets for both versions.

It is *not* expected that the packages would ever use this feature unless absolutely
necessary to support existing clients. Specifically, packages *should not*
adopt this syntax for tagging versions supporting the _latest GM_ Swift
version.

The package manager supports looking for any of the following marked tags, in
order of preference:

1. `MAJOR.MINOR.PATCH` (e.g., `1.2.0@swift-3.1.2`)
2. `MAJOR.MINOR` (e.g., `1.2.0@swift-3.1`)
3. `MAJOR` (e.g., `1.2.0@swift-3`)

### Version-specific Manifest Selection

The package manager will additionally look for a version-specific marked
manifest version when loading the particular version of a package, by searching
for a manifest in the form of `Package@swift-3.swift`. The set of markers
looked for is the same as for version-specific tag selection.

This feature is intended for use in cases where a package wishes to maintain
compatibility with multiple Swift project versions, but requires a
substantively different manifest file for this to be viable (e.g., due to
changes in the manifest API).

It is *not* expected the packages would ever use this feature unless absolutely
necessary to support existing clients. Specifically, packages *should not*
adopt this syntax for tagging versions supporting the _latest GM_ Swift
version.

In case the current Swift version doesn't match any version-specific manifest,
the package manager will pick the manifest with the most compatible tools
version. For example, if there are three manifests:

`Package.swift` (tools version 3.0)
`Package@swift-4.swift` (tools version 4.0)
`Package@swift-4.2.swift` (tools version 4.2)

The package manager will pick `Package.swift` on Swift 3, `Package@swift-4.swift` on
Swift 4, and `Package@swift-4.2.swift` on Swift 4.2 and above because its tools
version will be most compatible with future version of the package manager.
