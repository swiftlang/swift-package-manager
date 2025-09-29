# Resolving and updating dependencies

Coordinate and constrain dependencies for your package.

## Overview

The package manager records the result of dependency resolution in a file named `Package.resolved` at the top-level of the package.
When this file is present and you are resolving dependencies for the top-level (leaf) package of a dependency tree, the package manager uses the `Package.resolved` file as a cache of versions of the dependencies.
The Package.resolved file does not pin dependency versions for packages used as libraries, or are otherwise included as a dependency for another Swift project.
If the package is being resolved as a dependency from another package, its own `Package.resolved` file is ignored during that resolution.

Most SwiftPM commands implicitly invoke dependency resolution before running, and cancel with an error if dependencies cannot be resolved.

### Resolving Dependencies

Run <doc:PackageResolve> to resolve the dependencies, taking into account the current version constraints in the `Package.swift` manifest and a `Package.resolved` resolved versions file.
For packages with a `Package.resolved` file, the `resolve` command resolves to those versions as long as they are still eligible.
If you want to explicitly use the dependencies written into `Package.resolved`, use the `--force-resolved-versions` when invoking `swift resolve`.
For example, to force the dependencies to align with the versions defined in `Package.resolved`, use:

```bash
swift package resolve --force-resolved-versions
```

If the resolved version's file changes (for example, because a teammate shared an update through source control), the next `resolve` command attempts to update the package dependencies to match that file.
In most cases, the resolve command performs no changes unless the `Package.swift` manifest or `Package.resolved` file has changed.

### Updating the dependencies

Run <doc:PackageUpdate> to update a package's dependencies to the latest eligible versions, which also updates the `Package.resolved` file.

### Coordinating versions of dependencies for your package

You can use `Package.resolved` to coordinate the versions of dependencies it uses for a leaf Swift project - one that isn't being used as a dependency.
For example, you can keep a `Package.resolved` file in source control, or resolve it locally and pass it to a container image build process, in order to ensure another build uses the same versions of dependencies.

The `Package.resolved` only helps to resolve dependencies to the specific versions it defines for leaf projects.
It does not provide any dependency pinning for libraries or packages that are used as dependencies for other Swift projects.
For example, if your package presents a library and has `Package.resolved` checked in, those versions are ignored by the package that depends on your library, and the latest eligible versions are chosen.
For more information on constraining dependency versions, see <doc:AddingDependencies>.

If a `Package.resolved` doesn't exist, each user or build system separately resolves dependency versions, only updating when they run <doc:PackageUpdate>, and new users start with the latest eligible version of each dependency.
If the `Package.resolved` file does exist, any command that requires dependencies (for example, <doc:SwiftBuild> or <doc:SwiftRun>) attempts to resolve the versions of dependencies recorded in the file.
