# Dependency Mirrors

Dependency mirrors let Swift Package Manager fetch dependencies from alternate locations without modifying the package manifest.

## Overview
Dependency mirrors allow Swift Package Manager to fetch a package dependency from an alternate location without modifying the package manifest. This is useful in environments where dependencies must be fetched from internal mirrors, cached repositories, or alternate hosting locations. For more information about declaring dependencies, see <doc:AddingDependencies>.

Dependency mirrors are commonly used when working in corporate or restricted network environments, when redirecting dependencies to internal mirrors, or when controlling where dependencies are sourced from without modifying existing package manifests.

Dependency mirrors are configured locally and apply only to the top-level package being built. Mirror configuration is stored outside the package manifest and is not shared when a package is published or checked into version control. Dependency mirrors apply to all versions of a dependency identity and can’t be scoped to individual versions.

During dependency resolution, Swift Package Manager transparently rewrites dependency source locations based on the configured mirrors, without modifying the package manifest. When a mirror is configured for a dependency, it is treated as authoritative and Swift Package Manager does not fall back to the original source location. Swift Package Manager resolves dependency versions according to the rules described in <doc:ResolvingPackageVersions>.


### Configuring dependency mirrors
Dependency mirrors are configured using Swift Package Manager’s local configuration commands. These commands allow you to map a package dependency identity or source location to an alternate location without modifying the package manifest. Commands such as <doc:SwiftBuild>, <doc:SwiftRun>, and <doc:PackageUpdate> trigger dependency resolution.


To configure a mirror, you register a mapping between the original dependency source and the mirror location. Once configured, Swift Package Manager automatically applies this mapping during dependency resolution.

For example, if a package depends on a repository hosted at a public Git URL, you can configure Swift Package Manager to fetch that dependency from an internal mirror instead. After setting the mirror, subsequent dependency resolution operations will use the mirrored location transparently, without requiring changes to the package’s dependency declarations.

Mirror configuration affects only the top-level package being built. Once a mirror is set, Swift Package Manager treats it as authoritative and does not fall back to the original source location.

### Inspecting a mirror configuration
Use `swift package config get-mirror` to look up the mirror for a specific
dependency identity or URL:

```bash
swift package config set-mirror --original <original-url-or-identity> --mirror <mirror-url-or-identity>
swift package config get-mirror --original <original-url-or-identity>
swift package config unset-mirror --original <original-url-or-identity>
```

Mirror configuration is stored locally and is not part of the package manifest.
### Understand configuration scope

Mirror configuration is persisted by Swift Package Manager and may be
applied from different configuration scopes (such as workspace-local or
shared configuration). The specific scope used is determined implicitly
by SwiftPM based on the command context and environment.

The mirror configuration commands do not provide explicit flags to select
a configuration scope.
