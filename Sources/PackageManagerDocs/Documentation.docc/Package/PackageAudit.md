# swift package audit

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
    @Available("Swift", introduced: "6.5")
}

Report deprecated products in the current package graph.

```
package audit [--package-path=<package-path>]
  [--cache-path=<cache-path>] [--config-path=<config-path>]
  [--security-path=<security-path>]
  [--scratch-path=<scratch-path>]
  [--swift-sdks-path=<swift-sdks-path>]
  [--toolset=<toolset>...]
  [--pkg-config-path=<pkg-config-path>...]
  [--enable-dependency-cache] [--disable-dependency-cache]
  [--enable-build-manifest-caching]
  [--disable-build-manifest-caching]
  [--manifest-cache=<manifest-cache>]
  [--enable-experimental-prebuilts]
  [--disable-experimental-prebuilts] [--verbose]
  [--very-verbose|vv] [--quiet] [--color-diagnostics]
  [--no-color-diagnostics] [--disable-sandbox] [--netrc]
  [--enable-netrc] [--disable-netrc]
  [--netrc-file=<netrc-file>] [--enable-keychain]
  [--disable-keychain]
  [--resolver-fingerprint-checking=<resolver-fingerprint-checking>]
  [--resolver-signing-entity-checking=<resolver-signing-entity-checking>]
  [--enable-signature-validation]
  [--disable-signature-validation] [--enable-prefetching]
  [--disable-prefetching]
  [--force-resolved-versions|disable-automatic-resolution|only-use-versions-from-resolved-file]
  [--skip-update] [--disable-scm-to-registry-transformation]
  [--use-registry-identity-for-scm]
  [--replace-scm-with-registry]
  [--default-registry-url=<default-registry-url>]
  [--configuration=<configuration>] [--=<Xcc>...]
  [--=<Xswiftc>...] [--=<Xlinker>...] [--=<Xcxx>...]
  [--triple=<triple>] [--sdk=<sdk>] [--toolchain=<toolchain>]
  [--swift-sdk=<swift-sdk>] [--sanitize=<sanitize>...]
  [--auto-index-store] [--enable-index-store]
  [--disable-index-store]
  [--enable-parseable-module-interfaces] [--jobs=<jobs>]
  [--use-integrated-swift-driver]
  [--explicit-target-dependency-import-check=<explicit-target-dependency-import-check>]
  [--build-system=<build-system>] [--=<debug-info-format>]
  [--enable-dead-strip] [--disable-dead-strip]
  [--disable-local-rpath] [--format=<format>]
  [--include-transitive[=<mode>]] [--allow-deprecations]
  [--version] [--help]
```

## Overview

`swift package audit` inspects the resolved package graph for products that
their producing packages have marked as unsupported using the
`deprecated:` parameter on `.library(...)`, `.executable(...)`, or
`.plugin(...)`. For each such product it reports the producing package, the
product type, an optional author-supplied message, an optional replacement,
and the list of root-package targets whose dependency chain reaches the
product.

Every entry is classified into one of three categories via the `transitive`
field:

- `direct` — at least one root-package target has a
  `.product(name:package:)` dependency on the deprecated product.
- `transitiveReachable` — no root target names the deprecated product
  directly, but a root target reaches it via another consumed product's
  internal target chain (for example, `MyApp → MyLib → OldProduct`).
- `transitiveUnreachable` — the deprecated product exists in the resolved
  graph but no root-target dependency chain touches it.

Direct violations are always reported. Whether transitive-reachable and
transitive-unreachable entries appear is controlled by
`--include-transitive` (see below).

For each `direct` or `transitiveReachable` entry the report includes a
`breadcrumb` field: one or more paths from a root-package target down to
the deprecated product. Each hop identifies either a root-package target
(`{package, target}`) or a product-boundary crossing (`{package, product}`).
`transitiveUnreachable` entries carry no `breadcrumb` because no reaching
path exists.

By default the command exits with a non-zero status when any deprecated
product is reported. Pass `--allow-deprecations` to always exit `0` on a
successful audit (load failures still exit non-zero). This is intended for
interactive human use; CI pipelines can rely on the default behavior to
turn a finding into a failing job.

To silence the graph-load-time deprecation warnings while running an audit,
`swift package audit` suppresses them internally so its structured report
is the sole surface for deprecation output. A consumer target's per-target
`.treatAllWarnings(as: .error)` setting does not prevent the audit from
completing.

### Output formats

`swift package audit --format text` (the default) groups results into up to
three sections in fixed order — "Directly consumed deprecated products:",
"Transitively reachable deprecated products:", "Transitively unreachable
deprecated products:" — each present only when it has entries. Within a
section, entries are grouped by producing package.

`swift package audit --format json` emits a structured document with
alphabetically-sorted keys at every level. Every entry has the fields
`package`, `product`, `transitive`, `type`, and `usedBy`; optional fields
`message`, `replacement`, and `breadcrumb` appear when present. The
`replacement` object always has `kind: "renamed"` and a `product` string;
a `package` field is included only for cross-package replacements.

For an in-depth guide to declaring deprecations in your own package and
migrating consumers of deprecated products, see <doc:DeprecatingProducts>.

- term **--format=\<format\>**:

*Set the output format ('text' or 'json'). Defaults to `text`.*


- term **--include-transitive[=\<mode\>]**:

*Include transitive violations in the report. When passed without a value,
selects the `reachable` mode. Accepted explicit values:*

*`reachable` — include direct + transitively-reachable violations (bare
`--include-transitive` is equivalent to this).*

*`all` — include direct + transitively-reachable + transitively-unreachable
violations.*

*`non-reachable` — include only transitively-unreachable violations,
skipping reachable ones (useful for surveying deprecated products that
are still in the graph but not yet consumed).*


- term **--allow-deprecations**:

*Exit with status 0 even when deprecated products are found. Load failures
still exit non-zero.*


- term **--package-path=\<package-path\>**:

*Specify the package path to operate on (default current directory). This changes the working directory before any other operation.*


- term **--cache-path=\<cache-path\>**:

*Specify the shared cache directory path.*


- term **--config-path=\<config-path\>**:

*Specify the shared configuration directory path.*


- term **--security-path=\<security-path\>**:

*Specify the shared security directory path.*


- term **--scratch-path=\<scratch-path\>**:

*Specify a custom scratch directory path. (default .build)*


- term **--swift-sdks-path=\<swift-sdks-path\>**:

*Path to the directory containing installed Swift SDKs.*


- term **--verbose**:

*Increase verbosity to include informational output.*


- term **--very-verbose|vv**:

*Increase verbosity to include debug output.*


- term **--quiet**:

*Decrease verbosity to only include error output.*


- term **--color-diagnostics|no-color-diagnostics**:

*Enables or disables color diagnostics when printing to a TTY.
By default, color diagnostics are enabled when connected to a TTY and disabled otherwise.*


- term **--disable-sandbox**:

*Disable using the sandbox when executing subprocesses.*


- term **--version**:

*Show the version.*


- term **--help**:

*Show help information.*
