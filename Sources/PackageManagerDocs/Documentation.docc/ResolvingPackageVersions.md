# ResolvingPackageVersions

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

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
