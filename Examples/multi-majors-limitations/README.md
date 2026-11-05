# Multi-major prototype: limitation probes

Each numbered directory is a self-contained root package that stresses one assumption of the
multi-major prototype. They are probes, not tests: several are *expected* to fail, and the useful
output is how and where they fail. The predictions in each `Package.swift` were written from reading
the prototype, not from running it, so treat them as hypotheses.

Nothing here needs the network. `Shared` and `SharedC` are local git repos with real version tags
(multi-major only applies to source-control dependencies; path dependencies have no majors).

## Setup

```sh
./setup-fixtures.sh        # creates /tmp/multi-major-fixtures/{Shared,SharedC}; safe to re-run
```

Then, using your prototype `swift-build` / `swift-run` (same way you run `Examples/multi-majors-prototype`):

```sh
swift run --package-path 01-aliased-names-probe probe
```

Look for the `[MultiMajor][1-Resolution]`, `[3-Graph]` and `[4-Aliasing]` lines alongside the program output.
Delete `.build` and `Package.resolved` between runs if you re-create the fixtures, since the tags are new commits.

## Shape of the fixtures

| Repo | Tags | Modules |
|------|------|---------|
| `Shared` | 1.0.0, 2.0.0, 3.0.0 | `Shared` -> `SharedSupport` (two modules, so aliasing has to chain) |
| `SharedC` | 1.0.0, 2.0.0 | `SharedC` -> `CSharedC` (C target, same symbol in both majors) |

`libs/LibOne|LibTwo|LibThree` each pin `Shared` to exactly one major and re-expose its `Token` type,
its `major`, and its process-global log, so a root can observe which major a library really got.

## The probes

Results are from running the prototype (edge-scoping approach, see below). "Measured" means observed, not predicted.

| # | Question | Measured outcome |
|---|----------|------------------|
| 01 | Can one package use both majors through their aliased names? Root depends on `Shared 1..<3` plus LibOne (v1) and LibTwo (v2). | **Yes, with an asymmetric spelling.** The root's own bucket is `Shared`; the other is `Shared_v1`. Both link and run, with isolated state. `canImport` says `yes` for every spelling, so it is not a reliable probe. |
| 02 | What happens when values from the two majors meet in one package? | Builds. `Shared_v1.Token` and `Shared_v2.Token` are distinct types. Build with `-Xswiftc -DMISMATCH` to see the compile error; the only bridge is primitive values. |
| 03 | Can a manifest declare the dependency twice, once per major? | **Resolves, then crashes in the graph.** Validation only warns (`duplicate dependency 'shared'`). The resolver decides `shared@1` and `shared@2` for both declarations. The graph then traps with `Duplicate values for key: 'shared_Shared'` (`ModulesGraph+Loading.swift`, `productDependencyMap`), because both declarations have the same name and the lookup key is `<name>_<product>`. This should be a diagnostic, not a crash. |
| 04 | Three majors at once, is global state isolated? | Works. `sharedMajor` is `1 2 3`, and each log only contains its own library's entries. |
| 05 | Does the bucket choice hold for a non-root package that uses both majors? | Works. `Middle` sees its own bucket as `Shared` (2.x) and LibOne's 1.x as `Shared_v1`. |
| 06 | Does aliasing protect against non-Swift symbol collisions? | **No.** The Swift side compiles; linking fails with `duplicate symbol '_shared_c_version'` between `CSharedC_v1.o` and `CSharedC_v2.o`. Module aliasing cannot rename symbols inside compiled C objects. |
| 07 | Baseline: two libraries on two majors, no direct declaration by the root. | Works. Same shape as `multi-majors-prototype`. |
| 08 | Same as 03, but each declaration gets its own explicit name (`.package(name: "SharedV1", ...)`, deprecated spelling). | **Works, symmetrically.** The root imports `Shared_v1` and `Shared_v2` directly, both link and run, state is isolated. This is the only way found so far for one package to name both buckets, with no new API. |

Run 05 and 06 from their `root/` subdirectory: `swift run swift-run --package-path 05-nonroot-uses-both/root root`.

## How multiple majors are resolved here (prototype heuristic)

A version range that spans majors (`1.0.0..<3.0.0`) means "1.x OR 2.x", which one PubGrub node cannot express.
Rather than rework the solver, the OR is decided up front with the heuristic the graph layer already used:
a dependency binds to the **highest** major its range reaches (`majorVersionIdentity`,
`resolvedPackage(for:consumer:)`). `PackageContainerConstraint.scopedToHighestMajor()` rewrites each versioned
source-control constraint to the scoped package `pkg@M`, with the range sliced to major M, at the points where
constraints become nodes (`PubGrubPackageContainer.incompatibilites`, `VersionBasedConstraint.constraints`, and the
two places in `processInputs`). The solver then only sees single-major scoped nodes. It is switched by
`PackageContainerConstraint.scopesToHighestMajor`.

Known limitations of the heuristic:

- **No fallback to a lower major.** If the highest major can't be satisfied, nothing tries a lower one.
- **Possible duplicate copies.** A `1..<3` dependent plus a dependent that needs 1.x gets both `@2` and `@1`, where
  one `@1` would satisfy both.
- **Highest major with no versions** (e.g. `1.0.0..<3.0.0` on a repo with only 1.x tags) fails instead of falling back.
- **C/non-Swift symbols collide** across majors (probe 06).
- **The undeclared bucket is reachable only through the flat module search path** (probes 01, 05), which may be accidental.
- Pins in `Package.resolved` are keyed by plain identity, so existing pins won't match scoped identities.

The earlier approach (keep a plain `shared` node, flag packages requested at two majors, widen the term to a union) is
still in the code but unused while the switch is on. It failed whenever a package pinned one major directly and a
dependency wanted another (a later single-major requirement narrowed the union back to one major), and with three
majors (the union is no longer a single major).

Fixes that were needed on the way, independent of the approach:

1. *Workspace*: the root's own dependencies were tracked under the plain identity while everything else used the
   scoped one, so the plain one was reported missing ("exhausted attempts").
2. *Aliasing*: `addMultiMajorAliases` aliases every module in a bucket, so `fillInRest` (which only runs when a
   product has an unaliased module) never gave `Shared` the alias for its sibling `SharedSupport`. Each module now
   gets the full alias set.

## Spelling in the root: `Shared` vs `Shared_v1`

The root's compile is given `-module-alias Shared=Shared_v2`, and the compiler rejects `import Shared_v2` for an aliased
module ("use 'Shared' instead"). The bucket the root did not declare has no alias entry, so it is spelled `Shared_v1`.
Probe 08 shows one way a package can already get symmetric spelling today: declare the dependency once per major
with distinct explicit names. Each declaration's own range then picks its own bucket, and because the target depends
on two same-named modules from different products, the build uses the renamed names directly (no alias entry), so
`import Shared_v1` and `import Shared_v2` both work. The cost is the deprecated `.package(name:url:...)` spelling, and
nothing stops two declarations from sharing a name (probe 03 crashes instead of diagnosing it).

Other options to make this symmetric without that: skip the bucket alias entry for modules in root packages (plain `import Shared` then
stops working there), use the existing `directRefAliases` path (needs a consumer that sees both buckets), or add a
manifest opt-in. Libraries need the alias entry because their sources say `import Shared`.

## Not covered (ideas for next probes)

- Registry and branch/revision requirements (`supportedMajorVersions` is `[]` for those).
- Macros, plugins, and executable products that come from a multi-major package.
- Test targets that `@testable import` an aliased module.
- Traits interacting with a scoped bucket (see the trait unification notes).
- `swift package update` / `Package.resolved` round-trips and `swift package edit` on a scoped bucket.
