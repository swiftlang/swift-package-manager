# Resolving and updating package versions

Coordinate and constrain dependencies for your package.

## Overview

The package manager records the result of dependency resolution in a `Package.resolved` file in the top-level of the package.
When this file is already present in the top-level, it is used when performing dependency
resolution, rather than the package manager finding the latest eligible version
of each package.
Most SwiftPM commands implicitly invoke dependency resolution before running, and cancel with an error if dependencies cannot be resolved.

### Resolving Dependencies

Run <doc:PackageResolve> to resolve the dependencies, taking into account the current version constraints in the `Package.swift` manifest and a `Package.resolved` resolved versions file.
For packages with a `Package.resolved` file, the `resolve` command resolves to those versions as long as they are still eligible.

If the resolved version's file changes (for example, because a teammate shared an update through source control) the next `resolve` command updates the package dependencies to match that file.
In most cases the resolve command performs no changes unless the `Package.swift` manifest or `Package.resolved` file changed.

### Updating the dependencies

Running <doc:PackageUpdate> updates all dependencies to the latest eligible versions and updates the `Package.resolved` file accordingly.

### Coordinating versions of dependencies for your package

Keep the `Package.resolved` file in source control to coordinate specific dependencies for direct consumers of the package.
If a `Package.resolved` doesn't exist, each user separately resolves dependency versions, only updating when they run <doc:PackageUpdate>, and new users start with the latest eligible version of each dependency.
If the `Package.resolved` file does exist, any command that requires dependencies (for example, <doc:SwiftBuild> or <doc:SwiftRun>) attempts to resolve the versions of dependencies recorded in the file.

The `Package.resolved` doesn't constrain upstream dependencies of the package. 
For example, if your package presents a library and has `Package.resolved` checked in, that is ignored by the package depending on your library.
The the package depending on your package, only the dependency version constraints are used.
For more information on constraining dependency versions, see <doc:AddingDependencies>.

