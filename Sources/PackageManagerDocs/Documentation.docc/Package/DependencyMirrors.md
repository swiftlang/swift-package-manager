# Dependency Mirrors

Dependency mirrors allow Swift Package Manager to fetch a dependency from an alternate location without modifying the package manifest. This can be useful in environments where dependencies need to be fetched from internal mirrors, cached repositories, or alternate hosting locations.

Dependency mirrors are configured locally and affect only the top-level package being built.

## When to use dependency mirrors

Dependency mirrors are commonly used in the following scenarios:

- Accessing dependencies from internal or corporate-hosted mirrors
- Working in environments with restricted network access
- Redirecting dependency URLs without modifying existing package manifests

## Configuring dependency mirrors

Dependency mirrors are configured using Swift Package Manager commands. These commands allow setting, querying, and removing mirror configurations for package dependencies:

- ``swift package config set-mirror``
- ``swift package config get-mirror``
- ``swift package config unset-mirror``

Mirror configuration is stored locally and is not part of the package manifest.

## Scope and safety considerations

Dependency mirrors apply only to the top-level package being built. Dependencies cannot define or override mirror configurations for downstream packages.

Because mirror configuration is local and external to the package manifest, it is not shared when a package is published or checked into version control.

## Learn more

For the complete design and behavior details, see the Swift Evolution proposal [SE-0219: Package Manager Dependency Mirroring](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0219-package-manager-dependency-mirroring.md).

