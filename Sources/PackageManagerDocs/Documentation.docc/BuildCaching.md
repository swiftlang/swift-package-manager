# Build Caching

Configure build caching to speed up common workflows.

## Overview

During many common workflows, the build of a package may repeat a task which a previous build ran with identical inputs. For example:
- Locally switching between two different branches, incrementally rebuilding large parts of the package each time
- Building the same code across several git worktrees, each of which starts with an empty build folder
- Repeatedly building the same code in a CI environment which performs a clean build each time it's invoked

Rerunning previously executed tasks in these cases is wasteful and reduces development velocity. Furthermore, these are all workflows which do not benefit from traditional incremental builds, which rely on timestamp-based invalidation and reusing intermediates in the build directory. To accelerate these workflows, SwiftPM supports content based caching for task types including Swift and C compilation. The build system computes a content-based cache key derived from the task's inputs (sources, compiler command lines, imported modules, etc.) and is able to quickly replay results when there is a cache hit.

### Configuring Caching

SwiftPM provides three ways to configure compilation caching:

- Global configuration, via the `swift package build-cache configure` subcommand using the `--global` flag. This configuration affects all builds run using SwiftPM.
- Package-local configuration via the `swift package build-cache configure` subcommand. This affects all builds run for a particular package. Package-local configuration options override any global options.
- Per-build configuration via command line options. These only affect a single build, and override any package-local or global options.

### Configuration Options

- Enable or disable caching:
    - Global: `swift package build-cache configure --global --enable-caching`/`--disable-caching`
    - Package-local: `swift package build-cache configure --enable-caching`/`--disable-caching`
    - Per-build: `--enable-build-caching`/`--disable-build-caching`
        
- Enable or disable prefix mapping, which canonicalizes paths on compiler command lines and allows multiple instances of a package at different file paths to share cached outputs:
    - Global: `swift package build-cache configure --global --enable-prefix-mapping`/`--disable-prefix-mapping`
    - Package-local: `swift package build-cache configure --enable-prefix-mapping`/`--disable-prefix-mapping`
    - Per-build: `--enable-build-cache-prefix-mapping`/`--disable-build-cache-prefix-mapping`
        
- Set the path to the build cache, which defaults to a subdirectory of SwiftPM's configuration directory:
    - Global: `swift package build-cache configure --global --path <path>`
    - Package-local: `swift package build-cache configure --path <path>`
    - Per-build: `--enable-build-caching`/`--disable-build-caching`
        
- Set a size limit for the cache, either in absolute terms (e.g. 50G) or as a percentage of available disk space (e.g. 10%):
    - Global: `swift package build-cache configure --global --size-limit <limit>`
    - Package-local: `swift package build-cache configure --size-limit <limit>`
    - Per-build: `--build-cache-size-limit <limit>`

- Enable or disable diagnostic remarks which emit information about cache hits and misses in the build log:
    - Global: `swift package build-cache configure --global --enable-diagnostic-remarks`/`--disable-diagnostic-remarks`
    - Package-local: `swift package build-cache configure --enable-diagnostic-remarks`/`--disable-diagnostic-remarks`
    - Per-build: `--enable-build-cache-diagnostic-remarks`/`--disable-build-cache-diagnostic-remarks`
