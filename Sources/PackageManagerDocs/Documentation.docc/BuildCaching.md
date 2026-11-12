# Configuring build caching

Reuse compilation results across branches, worktrees, and continuous integration builds to speed up repeated builds.

## Overview

Many workflows compile the same code more than once. Examples include:

- Locally switching between two branches, incrementally rebuilding large parts of the package each time
- Building the same code across several Git worktrees, each of which starts with an empty build directory
- Repeatedly building the same code in a continuous integration (CI) environment that does a clean build on every run

Traditional incremental builds don't help in these workflows,
because they rely on timestamps and on intermediate files in the build directory.
SwiftPM instead supports content-based caching
for tasks such as Swift and C compilation.
The build system computes a cache key from each task's inputs,
including sources, compiler command lines, and imported modules.
When a task's cache key matches a stored result,
the build system replays that result instead of rerunning the task.
This is a cache hit.

Build caching is off by default.
You turn it on for a package, for all packages, or for a single build.
Caching works only with the Swift Build build system, which is the default.
If you build with `--build-system native`,
SwiftPM ignores the caching settings and prints a warning.

### Choose a configuration scope

You can configure build caching in three ways:

- Set global configuration with the <doc:PackageBuildCacheConfigure> command and the `--global` option. Global configuration affects all builds that SwiftPM runs.
- Set package-local configuration with the <doc:PackageBuildCacheConfigure> command. Package-local configuration affects all builds of that package and overrides global options.
- Set per-build configuration with command-line options. These options affect only a single build and override package-local and global options.

SwiftPM merges the scopes for each setting. For example, you can turn on caching globally and set a different cache path that applies to a single package.

To see the settings that apply to your next build, run <doc:PackageBuildCacheGetConfiguration>. To remove stored settings, run <doc:PackageBuildCacheResetConfiguration>. Add the `--global` option to remove the global settings instead of the package-local ones.

### Turn on build caching

Turn on caching when you repeat builds of the same code.
Common cases include switching branches, building several worktrees, and running clean CI builds.

To turn on caching for the current package:

1. Run `swift package build-cache configure --enable-caching`. Add `--global` to turn on caching for every package.
2. Build as usual, for example with `swift build`.
3. Confirm the setting with <doc:PackageBuildCacheGetConfiguration>. The first line of the output reads `build cache: enabled`. The remaining lines show the cache path, size limit, diagnostic remarks, and prefix mapping settings that apply.

To turn caching off again, run `swift package build-cache configure --disable-caching`.

To turn on caching for a single build, pass `--enable-build-caching` to <doc:SwiftBuild>, <doc:SwiftTest>, or <doc:SwiftRun>. Pass `--disable-build-caching` to turn it off for a single build.

### Share results between checkouts

Each Git worktree and each CI checkout lives at a different path. Compiler command lines contain file paths, and SwiftPM derives the cache key from those command lines. Prefix mapping normalizes the paths so that copies of a package at different locations share cached results.

SwiftPM turns prefix mapping on whenever you turn on caching.
To turn it off, run `swift package build-cache configure --disable-prefix-mapping`.
To turn it back on, run `swift package build-cache configure --enable-prefix-mapping`.

For a single build, pass `--disable-build-cache-prefix-mapping` or `--enable-build-cache-prefix-mapping`.

### Choose where the cache lives

By default, SwiftPM keeps the cache in a `build-cache` subdirectory of its shared cache directory.
To find the exact location, run <doc:PackageBuildCacheInfo>.

> Warning: `swift package build-cache clean` deletes the entire cache directory. Don't point the cache at a directory that holds other files.

To change the cache path:

1. Run `swift package build-cache configure --path /path/to/cache`. Specify an absolute path. Add `--global` to apply the path to every package.
2. Check the result with <doc:PackageBuildCacheGetConfiguration>. The `path:` line shows the location.

For a single build, pass `--build-cache-path /path/to/cache`.

To see how large the cache is, run <doc:PackageBuildCacheInfo>. It prints the cache path and its size on disk.

To delete the cache, run <doc:PackageBuildCacheClean>.

The <doc:PackageClean> command is separate. It deletes build artifacts for the package.

### Limit the cache size

A cache that grows without bounds can fill your disk. When the cache exceeds its size limit, the build prunes entries to bring it back under the limit. If you don't set a limit, the cache can use up to half of the available disk space.

Set the limit as an absolute size or as a percentage of available disk space:

```bash
swift package build-cache configure --size-limit 50G
swift package build-cache configure --size-limit 10%
```

A percentage must be between `0` and `100`. Add `--global` to apply the limit to every package. For a single build, pass `--build-cache-size-limit 50G`.

### Find out why a build missed the cache

If a cached build is slower than you expect, some tasks can miss the cache.
Use diagnostic remarks to report cache hits and misses in the build log.

To see the remarks:

1. Turn on the remarks by running `swift package build-cache configure --enable-diagnostic-remarks`. For a single build, pass `--enable-build-cache-diagnostic-remarks` instead.
2. Run the build with `--verbose`. The remarks don't appear in the default output.
3. Search the build log for lines that mention a cache hit or miss.

When a task misses the cache, the log shows the key that SwiftPM looked up:

```text
info: local cache miss for key: 0~rgEvRQ4NHKTB9UMArAI-Tp8Zoqshp2QC-54Fkass0Vhz...
info: replay cache miss
```

When a task hits the cache, the log shows that the build replayed the stored result:

```text
info: replay cache hit
```

To record cache keys in a trace, also pass `--trace-events-file` with a path. The trace then includes each task's cache key, the component that computed the key, and the cache location. If the same task has a different key in two builds, one of its inputs changed.

To turn the remarks off, run `swift package build-cache configure --disable-diagnostic-remarks`.

### Use caching in continuous integration

A CI build usually starts from a clean checkout, so the build directory has nothing to reuse.

To use caching in a CI build:

1. Turn on caching in the build command with `--enable-build-caching`.
2. Set `--build-cache-path` to a directory that your CI system saves and restores between runs.
3. Set `--build-cache-size-limit` so the saved cache stays a manageable size.

> Important: Anyone who can modify the cache can change your compiler outputs. On shared CI machines, restrict write access to the cache directory.

For example:

```bash
swift build --enable-build-caching \
  --build-cache-path /path/to/saved/cache \
  --build-cache-size-limit 20G
```

For more information on running SwiftPM in CI, see <doc:ContinuousIntegration>.

### Look up per-build options

Per-build options apply to one invocation and override package-local and global settings.
Pass the following options to <doc:SwiftBuild>, <doc:SwiftTest>, or <doc:SwiftRun>:

- term Caching: Turns build caching on or off. Pass `--enable-build-caching` or `--disable-build-caching`.
- term Prefix mapping: Shares cached results between copies of a package at different paths. Pass `--enable-build-cache-prefix-mapping` or `--disable-build-cache-prefix-mapping`.
- term Cache path: Sets the cache location. Pass `--build-cache-path <path>`.
- term Size limit: Caps the cache size. Pass `--build-cache-size-limit <limit>`.
- term Diagnostic remarks: Reports cache hits and misses in the build log. Pass `--enable-build-cache-diagnostic-remarks` or `--disable-build-cache-diagnostic-remarks`.
