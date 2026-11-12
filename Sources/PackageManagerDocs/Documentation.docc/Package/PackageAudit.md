# swift package audit

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
}

Check dependencies for known security vulnerabilities.

```
package audit [--package-path=<package-path>]
  [--severity-threshold=<low|moderate|high|critical>]
  [--format=<text|json>]
  [--ignore=<id>...]
  [--fail-on-unchecked]
  [--advisory-database=<url>]
  [--no-advisory-database]
  [--no-registry-advisories]
  [--verbose]
```

## Overview

`swift package audit` reads the resolved dependency graph of the package (the pins in `Package.resolved`), looks up
advisories for each resolved package version, and reports the findings. If the dependencies have not been resolved
yet, the command resolves them first. It does not build anything.

The graph is loaded with all traits enabled, and platform conditions are not evaluated, so dependencies that are only
used in another configuration are audited too.

Advisories come from two sources, and findings from both are merged:

- An OSV-compatible database, queried with the `SwiftURL` ecosystem for source control dependencies and for the
  repository URLs of registry dependencies. The default database is `https://api.osv.dev`.
- The package registry that provided a registry dependency, if it publishes advisories.

Branch- and revision-based dependencies can only be checked by a database that supports commit queries, and local
(path) dependencies are never checked; such packages are reported as *unchecked*. Pass `--verbose` to list them with
the reason.

For each finding, the text output shows the severity, the advisory ID and aliases, the summary, the package and its
resolved version, every dependency path to it, the patched versions, how it can be fixed, and a link to the advisory:

```
High      GHSA-xxxx-xxxx-xxxx (CVE-2026-12345)
          Regular expression denial of service in RegEx
Package   https://github.com/example/RegEx 1.4.2
Path      MyApp > PatternMatcher > RegEx
Fixed in  1.4.3
Fix       Run `swift package audit fix` (within current requirements)
More info https://osv.dev/vulnerability/GHSA-xxxx-xxxx-xxxx

Found 1 vulnerability (1 high) in 14 scanned packages.
```

With `--format json`, the command writes a single JSON object to standard output instead.

### Exit status

| Status | Meaning |
| --- | --- |
| 0 | No findings at or above the threshold, and (with `--fail-on-unchecked`) every package was checked |
| 1 | The command failed, for example because of a network error or an invalid configuration (SwiftPM's usual failure status) |
| 2 | Findings at or above the threshold, or unchecked packages with `--fail-on-unchecked` |

Advisories with an unknown severity meet any threshold, so that a missing severity never hides a finding. Ignored
advisories never affect the exit status.

### Configuring the advisory database

The advisory database is the first of:

1. the `--advisory-database` option;
2. the package's setting, stored in `.swiftpm/configuration/audit.json`;
3. the user's setting, stored in the shared SwiftPM configuration directory;
4. `https://api.osv.dev`.

Manage the settings with `swift package config`:

```
swift package config set-advisory-database <url> [--global]
swift package config unset-advisory-database [--global]
swift package config get-advisory-database [--global]
```

With `--global`, `set-advisory-database` and `unset-advisory-database` change the user's setting instead of the
package's. `get-advisory-database` prints the database that `swift package audit` uses when no
`--advisory-database` option is passed; with `--global`, the package's setting is not considered.

## Options

| Option | Description |
| --- | --- |
| `--severity-threshold <low\|moderate\|high\|critical>` | Lowest severity that causes a failing exit status (default: `low`). |
| `--format <text\|json>` | Output format (default: `text`). |
| `--ignore <id>` | Ignore an advisory by ID or alias. Can be repeated. |
| `--fail-on-unchecked` | Fail if any package could not be checked. |
| `--advisory-database <url>` | OSV-compatible database to query: an `https://` URL of a server implementing the OSV API, or a `file://` URL of a local directory or ZIP archive of OSV records. |
| `--no-advisory-database` | Do not query an OSV-compatible database. |
| `--no-registry-advisories` | Do not query package registries for advisories. |

`--no-advisory-database` and `--no-registry-advisories` cannot be used together.
