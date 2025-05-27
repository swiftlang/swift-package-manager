# Resolving package dependency failures

Understand dependency failure scenarios.

## Overview

You define constraints for dependencies when you add them to your package, and those constraints can not always be met.

Prior to running a build or test, or when you run <doc:PackageResolve>, the package manager walks through the dependencies in your package, and all their dependencies recursively, to build a complete list.
It then attempts to choose a version of each dependency that fits within the constraints of your package, and any constraints provided by your dependencies.

If all the dependencies are available and resolved, the versions are recorded locally in the file `Package.resolved`.
You can view these dependencies using the command <doc:PackageShowDependencies>, which provides a succint list of the entire set of dependencies.

If the dependencies can't be resolved, for example when the packages your package depends on have conflicting constraints, the package manager returns an error, describing the conflicting constraint: 
```
error: Dependencies could not be resolved because root depends on 'pkgb' 0.1.0.
'pkgb' 0.1.0 cannot be used because 'pkgb' 0.1.0 depends on 'pkga' 0.3.0 and root depends on 'pkga' 0.4.0.
```

Rework your dependencies, or update a package you want to depend upon, to resolve any conflicting constraints.

### Failure Scenarios

There are a variety of scenarios that may occur, including:

- term Inappropriate Versioning: A package may specify an inappropriate version for a release. 
  For example, a version is tagged `1.2.3`, but introduces extensive, breaking API changes that should be reflected by a major version bump to `2.0.0`.

- term Incompatible Major Version Requirements: A package may have dependencies with incompatible version requirements for the same package. 
  For example, if `Foo` depends on `Baz` at version `~>1.0` and `Bar` depends on `Baz` at version `~>2.0`, then there is no one version of `Baz` that can satisfy both requirements. 
  This situation often arises when a dependency shared by many packages updates to a new major version, and it takes a long time for all of those packages to update their dependency.

- term Incompatible Minor or Update Version Requirements: A package may have dependencies that are specified too strictly, such that version requirements are incompatible for different minor or update versions. 
  For example, if `Foo` depends on `Baz` at version `==2.0.1` and `Bar` depends on `Baz` at version `==2.0.2`, once again, there is no one version of `Baz` that can satisfy both requirements. 
  This is often the result of a regression introduced in a patch release of a dependency, which causes a package to lock that dependency to a particular version.

- term Namespace Collision: A package may have two or more dependencies that have the same name. 
  For example, a `Person` package depends on an `Addressable` package that defines a protocol for assigning a mailing address to a person, as well as an `Addressable` package that defines a protocol for speaking formally to another person.

- term Broken Software: A package may have a dependency with an outstanding bug that is impacting usability, security, or performance.
  This may simply be a matter of timeliness on the part of the package maintainers, or a disagreement about their expectations for the package.

- term Global State Conflict: A package may have two or more dependencies that presume to have exclusive access to the same global state.
  For example, one package may not be able to accommodate another package writing to a particular file path while reading from that same file path.

- term Package Becomes Unavailable: A package may have a dependency on a package that becomes unavailable.
  This may be caused by the source URL becoming inaccessible, or maintainers deleting a published version.
