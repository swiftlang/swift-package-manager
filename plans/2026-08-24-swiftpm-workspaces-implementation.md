# SwiftPM Workspaces — Implementation Plan

## Overview

Implement first-class workspaces in Swift Package Manager: a new `Workspace.swift` manifest declares multiple member packages with unified dependency resolution, shared build state, and consistent CLI ergonomics. Design is locked in `/Users/bkhouri/Documents/git/public/swiftlang/swift-evolution/proposals/NNNN-swiftpm-workspaces.md`.

**Delivery model:** one commit per slice on branch `bkhouri/t/main/poc_workspaces`. Strict linear order. No PRs created by this plan — Sam K creates the PR stack himself via `gh-stack` after the branch is complete.

**Gating:** all new DSL surface gated on `@available(_PackageDescription, introduced: 999.0)` using SwiftPM's existing `vNext` convention (`Sources/PackageModel/ToolsVersion.swift:39`). Graduation to a real tools-version is out of scope for this plan.

## Status (as of 2026-09-01)

| Phase | Slice | Status | Branch |
|---|---|---|---|
| 0 | Rename `Workspace` → `PackageWorkspace` | ✅ Done | `bkhouri/t/main/poc_workspaces_phase0` |
| 1 | Minimal Workspace (S01) | ✅ Done | `bkhouri/t/main/poc_workspaces_phase1` |
| 2 | `.package(workspaceMember:)` DSL (S02) | ✅ Done | `bkhouri/t/main/poc_workspaces_phase2` |
| 3 | `.package(workspaceInherited:)` DSL (S03) | ✅ Done — **augmented, not rewritten** (see phase note) | `bkhouri/t/main/poc_workspaces_phase3` |
| 4 | Case A — CWD inside member (S04) | ✅ Done | `bkhouri/t/main/poc_workspaces_phase4` |
| 5 | `--package` selector for `swift build` (S05) | ✅ Done | `bkhouri/t/main/poc_workspaces_phase5` |
| 6 | `swift test` in workspace (S06) | ✅ Done — includes `XUnitGenerator` per-package annotation and `swift test list --package` migration (on a separate branch) | `bkhouri/t/main/poc_workspaces_phase6` (+ follow-up branch) |
| 7 | `swift run` collisions | ✅ Done | `bkhouri/t/main/poc_workspaces_phase7` |
| 8 | `swift package resolve` + trailing warnings + workspace-scope originHash | ✅ Done | `bkhouri/t/main/poc_workspaces_phase8` |
| 8B | Workspace dependency overrides (`.swiftpm/configuration/workspace-overrides.json`) | ✅ Done — folds overrides file content into origin hash | `bkhouri/t/main/poc_workspaces_phase8_diverge-workspace_deps_override` |
| 8C | `swift package workspace override` subcommand (add / remove / list) | ✅ Done — POC scope, nested under `swift package workspace` | `bkhouri/t/main/poc_workspaces_phase8` |
| 8D | `workspace override` extended scope — member-level dep support | 🟡 In progress — TDD cycles 1-12 (see Phase 8D section) | `bkhouri/t/main/poc_workspaces_phase8_diverge-workspace_deps_override_add_subcommand` |
| 9 | `swift package workspace init` | ✅ Done — POC scope, nested under `swift package workspace` (respects `--package-path`) | `bkhouri/t/main/poc_workspaces_phase8` |
| 10 | `swift package show-dependencies` workspace awareness | ✅ Done — all four formats extended, coverage split between unit + e2e | `bkhouri/t/main/poc_workspaces_phase10` |
| 11 | `swift package update` workspace awareness | ✅ Done — `--package` selector + CWD focus + workspace-root routing | `bkhouri/t/main/poc_workspaces_phase11-make-package-update-workspace-aware` |
| 12 | `swift package clean` workspace awareness | ✅ Done — workspace-root `.build/` cleanup + info diagnostics + `--package` parity | `bkhouri/t/main/poc_workspaces_phase11-make-package-update-workspace-aware` (Phase 12 landed on the Phase 11 branch as follow-up) |
| 13 | `swift package describe` workspace awareness | ✅ Done — per-member iteration for text/json/mermaid + `--package` + CWD focus + `DescribedPackageDependency.workspaceInherited` case fix | `bkhouri/t/main/poc_workspaces_phase13-make-package-describe-workspace-aware` |
| 14 | `swift package dump-package` workspace awareness + `swift package workspace dump-workspace` | ✅ Done — `--package` selector + CWD focus + workspace-root ambiguity error; workspace manifest dump added alongside | `bkhouri/t/main/poc_workspaces_phase14-make-package-dump-package-workspace-aware` |
| 15 | Error paths + edge cases | ✅ Done — split into 15a (load-time errors), 15b (nested workspaces), 15c (`--multiroot-data-file` conflict + `--package-path` → `--project-path` rename), 15d (`edit`/`unedit` deferred + workspace-only DSL outside workspace) | `bkhouri/t/main/poc_workspaces_phase15-*` (multiple stack branches) |
| 16 | Per-member trait isolation + cross-package cycle detection | ✅ Done — unit + e2e coverage for `.workspaceMember` and `.workspaceInherited` trait isolation; e2e coverage for cycle detection through both DSL edges | `bkhouri/t/main/poc_workspaces_phase15-error-handling-workspace-cyclical-dependency` |

## Current State Analysis

The relevant machinery is partially present:

- **Internal `Workspace` class** at `Sources/Workspace/Workspace.swift:77` — public, imported by ~15 SwiftPM modules and libSwiftPM consumers, ~117 files reference the identifier. Stateful orchestrator for graph loading, resolution, checkouts.
- **Multi-root plumbing already works.** `PackageGraphRootInput.packages: [AbsolutePath]` at `Sources/PackageGraph/PackageGraphRoot.swift:19` is plural. PubGrub synthesizes a `<synthesized-root>` for >1 root at `PubGrubDependencyResolver.swift:180`. `WorkspaceLoader` protocol at `SwiftCommandState.swift:1425` is the extension point.
- **`--multiroot-data-file`** at `Options.swift:120` uses the same abstraction to load Xcode workspace files today — proven battle-tested code path.
- **Manifest loader is filename-agnostic.** `ManifestLoader.evaluateManifest()` at `ManifestLoader.swift:686` and `ToolsVersionParser.parse(manifestPath:)` at `ToolsVersionParser.swift:27` operate on any path.
- **Discovery** currently walks up from CWD looking for `Package.swift` (`SwiftCommandState.getWorkspaceRoot()` at `SwiftCommandState.swift:294`).
- **Package.resolved schema** at `Sources/PackageGraph/ResolvedPackagesStore.swift:30` is `[PackageIdentity: ResolvedPackage]` — already root-agnostic. No schema bump needed.
- **`.build/`, `.swiftpm/`, `Package.resolved`, `Packages/` locations** managed by `Workspace.Location` at `Sources/Workspace/Workspace+Configuration.swift:30`.
- **`PackageDependency.Kind`** at `Sources/PackageModel/Manifest/PackageDependencyDescription.swift:101` — three cases (`.fileSystem`, `.sourceControl`, `.registry`), unfrozen, forward-compatible.
- **Test infrastructure**: `MockWorkspace` at `Sources/_InternalTestSupport/MockWorkspace.swift` for unit tests; `Fixtures/<Feature>/` + `Tests/FunctionalTests/` for end-to-end CLI tests via `executeSwiftBuild()`.
- **BuildPlan FIXME** at `Sources/Build/BuildPlan/BuildPlan.swift:687`: `Package.resolved` location wrong for multiroot. Fixed in Slice 8.
- **Existing 999.0 gating** in `Sources/Runtimes/PackageDescription/PackageDescription.swift:487,528`, `PackageRequirement.swift:206`, `SupportedPlatforms.swift:74` — the pattern is proven.

## Desired End State

At completion of Slice 15 on branch `bkhouri/t/main/poc_workspaces`:

- A user with `// swift-tools-version: 999.0` can write `Workspace.swift` at a directory root, list members and workspace-wide deps, and run `swift build`, `swift test`, `swift run`, `swift package resolve`, `swift package init workspace` with the semantics locked in the SE proposal.
- Members reference each other via `.package(workspaceMember:)` and inherit workspace deps via `.package(workspaceInherited:)`.
- Discovery, Case A, `--package` selector, xUnit aggregation, trailing warnings, error paths, `--path`/`--package-path` deprecation, `--multiroot-data-file` conflict rejection, nested-workspace rejection — all working.
- Internal `Workspace` class renamed to `PackageWorkspace` with a deprecated typealias.
- Every existing SwiftPM test still passes on every slice commit.
- One fixture directory per slice under `Fixtures/Workspaces/S<NN>_*/` (Slices 1-15), with subdirectories per scenario as needed. Functional tests in `Tests/FunctionalTests/WorkspaceFeatureTests.swift` cover each slice's behavior.

## Key Discoveries

- `PackageGraphRootInput.packages` is already plural — feed N members, PubGrub synthesizes a virtual root. Zero resolver changes needed.
- `Package.resolved` V3 schema is root-agnostic — a flat `[PackageIdentity: ResolvedPackage]` map. Workspace-level shared lockfile fits without a schema bump.
- `ManifestLoader.evaluateManifest()` and `ToolsVersionParser.parse()` are filename-agnostic — `Workspace.swift` reuses them.
- `WorkspaceLoader` protocol at `SwiftCommandState.swift:1425` is the correct extension point — `SwiftWorkspaceLoader` sits alongside existing `XcodeWorkspaceLoader`.
- `PackageDependency.Kind` is unfrozen — new cases are source-compatible (warnings, not errors) for downstream exhaustive switches.
- `999.0` availability gating is an established SwiftPM convention.
- `Fixtures/*/` fixtures use `executeSwiftBuild()` which invokes the built-from-source SwiftPM, so 999.0-tools-version fixtures work in tests without special infrastructure.

## What We're NOT Doing

- `swift package edit` / `swift package unedit` under workspace — implemented in Slice 15d as a hard-error pointing at `swift package workspace override` (the workspace-scoped replacement for the "redirect a dep to a local checkout" use case). Not a "not yet supported" deferral: the workspace-scoped replacement is already shipped in Phase 8C.
- Nested workspace *support* (Slice 15 emits rejection error; support is post-MVP).
- Migration of member `Package.resolved` pins into workspace `Package.resolved` (member files ignored + trailing warning per SE proposal; migration deferred).
- Rich IDE integration API (Slice 1 ships minimal `WorkspaceManifest` public type + `discoverWorkspaceRoot`/`loadWorkspaceManifest`; broader IDE lifecycle hooks are post-MVP).
- SourceKit-LSP or Xcode consumer-side changes (those are separate PRs in their respective repos).
- Documentation in the SwiftPM user guide (separate follow-up; not required to compile+test the feature).
- Graduation from `999.0` to a real tools-version (`6.5` or similar) — happens at ship time, after SE acceptance.
- Removal of `--package-path` or `--multiroot-data-file` — both retained with deprecation warnings; hard removal is post-MVP.
- Rebuilding the manifest cache to distinguish `Workspace.swift` from `Package.swift` — reuses existing cache path with the new filename as an additional key.

## Implementation Approach

The design decomposes into cleanly-separable slices because SwiftPM's architecture is layered: DSL → JSON → model → workspace rewrite → graph → resolver → build system → CLI. Each slice touches one or two layers, keeping commits reviewable.

The rewrite pass (member manifests → concrete deps) is the architectural keystone: it lets the resolver, graph, and build system remain workspace-unaware. All workspace-specific reasoning is confined to `PackageWorkspace` extensions added in Slices 1-3.

Discovery hooks into `SwiftCommandState.getWorkspaceRoot()` — a single method today, extended to prefer `Workspace.swift` when present.

CLI selection (`--package`) piggybacks on the existing plural `rootPackages` — no new CLI plumbing needed except argument parsing.

### CI/Validation gates per slice

Each commit must pass, before landing:

```
swift build --disable-sandbox
swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure
```

Additionally, the slice's fixture at `Fixtures/Workspaces/S<NN>_<name>/` must exist and its corresponding functional test in `Tests/FunctionalTests/WorkspaceFeatureTests.swift` must pass.

Any regression in the full existing test suite blocks the slice.

---

## Phase 0: Rename Prerequisite — `Workspace` → `PackageWorkspace`

### Overview

Mechanical rename of the internal `Workspace` class to `PackageWorkspace`. Module stays `Workspace`. Deprecated typealias preserves compat for one release.

### Changes Required

#### 1. Rename the class
**File**: `Sources/Workspace/Workspace.swift`
**Change**: Rename `public class Workspace` → `public class PackageWorkspace`. Update all `self`-reference sites within the class and extensions.

```swift
public class PackageWorkspace {
    // existing body unchanged
}
```

#### 2. Add deprecated typealias
**File**: `Sources/Workspace/Workspace.swift` (end of file)

```swift
@available(*, deprecated, renamed: "PackageWorkspace")
public typealias Workspace = PackageWorkspace
```

#### 3. Rename in extensions and companion files
**Files**: `Sources/Workspace/Workspace+*.swift` (Configuration, Dependencies, State, etc.) — every `extension Workspace` becomes `extension PackageWorkspace`.

#### 4. Update all internal consumers
**Approach**: `grep -rl '\bWorkspace\b' Sources/ Tests/` → mechanical replacement of `Workspace(` constructions, `Workspace.` static references, and type annotations. Type-usage sites (e.g. `let ws: Workspace`) become `let ws: PackageWorkspace`. Use IDE-driven rename where possible.

Blast radius: ~117 files. Key consumers to audit:
- `Sources/CoreCommands/SwiftCommandState.swift`
- `Sources/Commands/*.swift`
- `Sources/_InternalTestSupport/MockWorkspace.swift`
- `Sources/Workspace/*.swift`
- `Tests/WorkspaceTests/*.swift`

#### 5. Verify deprecation typealias
**File**: `Tests/WorkspaceTests/PackageWorkspaceDeprecationTests.swift` (new)

```swift
import Testing
import Workspace

@Test
func deprecatedTypealiasCompiles() async throws {
    // The typealias is expected to emit a deprecation warning at use sites.
    // This test verifies the typealias exists and remains source-compatible.
    let _: Workspace.Type = PackageWorkspace.self
}
```

### Success Criteria

#### Automated Verification:
- [x] `swift build --disable-sandbox` succeeds
- [x] `swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure` — full suite green
- [x] `PackageWorkspaceDeprecationTests.deprecatedTypealiasCompiles` passes
- [ ] Add `PackageWorkspaceRenameTests.noOldClassNameRemains` that shells out to `grep -rn '\bclass Workspace\b' Sources/Workspace/` and asserts zero hits — mechanical regression guard against reintroducing the old declaration — **deferred**, not blocking the rename
- [ ] Add `PackageWorkspaceRenameTests.typealiasEmitsDeprecationWarning` that compiles a small Swift snippet using the `Workspace` typealias in a subprocess with `-warnings-as-errors` OR captures compiler diagnostics stream and asserts the deprecation diagnostic is present — **deferred**, tracked as follow-up

#### Manual Verification:
(none — all criteria automated)

---

## Phase 1: Minimal Workspace

### Overview

Land the smallest end-to-end slice that proves the concept: a two-member workspace with no cross-refs and no inherited deps builds via `swift build` at workspace root.

Introduces: DSL types in `PackageDescription` (gated `999.0`), `WorkspaceManifest` model, `Workspace.swift` filename recognition, `PackageWorkspace.loadWorkspaceManifest()` public API, discovery walk-up integration, MockWorkspace scaffolding.

**Scope note:** Slice 1 is the widest slice in the plan (~10 files across 5 subsystems). This is unavoidable — the DSL, model, evaluator hookup, discovery, and public API must all exist together for the end-to-end fixture test to pass. Reviewers should approach the commit in this order: (1) DSL types, (2) model type, (3) manifest loader hookup, (4) PackageWorkspace public API, (5) SwiftCommandState discovery hook, (6) MockWorkspace test support, (7) fixture + functional test. All later slices are strictly narrower.

### Basic validation performed in this slice

Even though "error paths" is nominally Slice 15, some validation is a load-time invariant that must exist from Slice 1 or `loadWorkspaceManifest` cannot function:

- Empty `members: []` → hard error at load (Slice 15 tests it; Slice 1 implements the check).
- Absolute member paths → hard error at load.
- Duplicate `PackageIdentity` across members → hard error.
- Member path does not exist / has no `Package.swift` → hard error.

Slice 15 adds fixtures + tests for each of these; Slice 1 ships the enforcing code.

### Changes Required

#### 1. DSL types in PackageDescription
**File**: `Sources/Runtimes/PackageDescription/Workspace.swift` (new)

```swift
@available(_PackageDescription, introduced: 999.0)
public struct Workspace: Sendable {
    public let members: [Member]
    public let dependencies: [Package.Dependency]

    public init(
        members: [Member],
        dependencies: [Package.Dependency] = [],
    ) {
        self.members = members
        self.dependencies = dependencies
    }
}

@available(_PackageDescription, introduced: 999.0)
extension Workspace {
    public struct Member: Sendable, ExpressibleByStringLiteral {
        public let path: String
        public let ignoredStateDirectories: Set<StateDirectoryKind>

        public init(stringLiteral value: String) {
            self.path = value
            self.ignoredStateDirectories = []
        }

        public init(
            path: String,
            ignoredStateDirectories: Set<StateDirectoryKind> = [],
        ) {
            self.path = path
            self.ignoredStateDirectories = ignoredStateDirectories
        }
    }

    public static func member(
        path: String,
        ignoredStateDirectories: Set<StateDirectoryKind> = [],
    ) -> Member {
        Member(path: path, ignoredStateDirectories: ignoredStateDirectories)
    }

    public enum StateDirectoryKind: Sendable {
        case build
        case packageResolved
        case packages
        case swiftpmConfig
    }
}
```

#### 2. Serialization
**File**: `Sources/Runtimes/PackageDescription/PackageDescriptionSerialization.swift`

Add serialization cases for `Workspace`. The serialization format follows the existing pattern (JSON dumped to stdout on manifest evaluation).

**File**: `Sources/Runtimes/PackageDescription/PackageDescriptionSerializationConversion.swift`

Add matching deserialization.

#### 3. WorkspaceManifest model
**File**: `Sources/PackageModel/Manifest/WorkspaceManifest.swift` (new)

```swift
public struct WorkspaceManifest: Sendable {
    public let path: AbsolutePath
    public let toolsVersion: ToolsVersion
    public let members: [Member]
    public let dependencies: [PackageDependency]

    public struct Member: Sendable {
        public let identity: PackageIdentity
        public let path: AbsolutePath
        public let ignoredStateDirectories: Set<StateDirectoryKind>
    }

    public enum StateDirectoryKind: Sendable, Hashable {
        case build
        case packageResolved
        case packages
        case swiftpmConfig
    }
}
```

#### 4. Manifest loader integration
**File**: `Sources/PackageLoading/ManifestLoader.swift`

Add public method:
```swift
public func loadWorkspaceManifest(
    at path: AbsolutePath,
    toolsVersion: ToolsVersion,
    identityResolver: IdentityResolver,
    observabilityScope: ObservabilityScope,
) async throws -> WorkspaceManifest
```

Reuse `evaluateManifest()`; the JSON output is parsed by a new `WorkspaceManifestJSONParser` type in the same directory. Filename convention: `Workspace.swift` (with version-specific `Workspace@swift-X.Y.swift` support via the same regex adaptation in `ToolsVersionParser.swift:640` — treat both "Package" and "Workspace" as valid basenames).

#### 5. Discovery hook
**File**: `Sources/CoreCommands/SwiftCommandState.swift:294`

Update `getWorkspaceRoot()`:
```swift
public func getWorkspaceRoot() throws -> PackageGraphRootInput {
    // Existing --multiroot-data-file check (unchanged for this slice)
    if let workspace = options.locations.multirootPackageDataFile {
        // ...existing behavior
    }

    // NEW: workspace discovery walk-up
    if let workspaceRoot = PackageWorkspace.discoverWorkspaceRoot(
        from: fileSystem.currentWorkingDirectory ?? .root,
        fileSystem: fileSystem,
    ) {
        let manifest = try await loadWorkspaceManifest(at: workspaceRoot)
        return PackageGraphRootInput(
            packages: manifest.members.map(\.path),
            traitConfiguration: self.traitConfiguration,
        )
    }

    // Existing single-package walk-up (unchanged)
    // ...
}
```

#### 6. PackageWorkspace public API
**File**: `Sources/Workspace/PackageWorkspace+Discovery.swift` (new)

```swift
extension PackageWorkspace {
    public static func discoverWorkspaceRoot(
        from path: AbsolutePath,
        fileSystem: FileSystem,
    ) -> AbsolutePath? {
        var current = path
        while true {
            let candidate = current.appending("Workspace.swift")
            if fileSystem.exists(candidate) {
                return current
            }
            if current == .root { return nil }
            current = current.parentDirectory
        }
    }

    public func loadWorkspaceManifest(
        at path: AbsolutePath,
        observabilityScope: ObservabilityScope,
    ) async throws -> WorkspaceManifest {
        // Uses ManifestLoader.loadWorkspaceManifest()
        // Validates: at least one member, no duplicate identities, paths exist,
        // no member paths are absolute, no nested Workspace.swift in member subtrees.
    }
}
```

#### 7. Fixture
**Directory**: `Fixtures/Workspaces/S01_MinimalTwoMembers/` (new)

```
Fixtures/Workspaces/S01_MinimalTwoMembers/
  Workspace.swift          # tools-version 999.0, lists two members
  packages/
    lib-a/
      Package.swift        # standard library package
      Sources/lib-a/lib-a.swift
    lib-b/
      Package.swift
      Sources/lib-b/lib-b.swift
```

Concrete file contents:

`Workspace.swift`:
```swift
// swift-tools-version: 999.0
import PackageDescription

let workspace = Workspace(
    members: [
        "packages/lib-a",
        "packages/lib-b",
    ],
)
```

`packages/lib-a/Package.swift`:
```swift
// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    targets: [
        .target(name: "LibA"),
    ],
)
```

`packages/lib-a/Sources/LibA/LibA.swift`:
```swift
public enum LibA {
    public static let greeting = "Hello from lib-a"
}
```

`packages/lib-b/*` mirrors `lib-a` with names substituted.

#### 8. MockWorkspace test-support additions
**File**: `Sources/_InternalTestSupport/MockWorkspace.swift`

Extend the mock to model a workspace scenario:

```swift
public final class MockWorkspace {
    // Existing:
    let roots: [MockPackage]
    let packages: [MockPackage]
    // NEW:
    let workspaceManifest: MockWorkspaceManifest?

    public init(
        // ... existing params ...
        workspace: MockWorkspaceManifest? = nil,
    ) { ... }
}

public struct MockWorkspaceManifest: Sendable {
    public let members: [MockWorkspaceMember]
    public let dependencies: [MockDependency]

    public init(
        members: [MockWorkspaceMember],
        dependencies: [MockDependency] = [],
    )
}

public struct MockWorkspaceMember: Sendable {
    public let path: String
    public let ignoredStateDirectories: Set<WorkspaceManifest.StateDirectoryKind>

    public init(
        path: String,
        ignoredStateDirectories: Set<WorkspaceManifest.StateDirectoryKind> = [],
    )
}
```

When `workspaceManifest` is non-nil, `MockWorkspace.create()` writes a `Workspace.swift` file at the sandbox root and lays out members according to the member list. Existing tests unaffected (default `nil`).

#### 9. Unit tests (Slice 1's unit-test companion to the fixture test)
**File**: `Tests/WorkspaceTests/WorkspaceManifestTests.swift` (new)

Uses `MockWorkspace` + `InMemoryFileSystem`. Tests cover the load-time invariants without needing a real subprocess:

```swift
@Test
func loadWorkspaceManifest_withTwoMembers_resolvesIdentitiesAndPaths() async throws { ... }

@Test
func loadWorkspaceManifest_withEmptyMembers_errors() async throws { ... }

@Test
func loadWorkspaceManifest_withAbsoluteMemberPath_errors() async throws { ... }

@Test
func loadWorkspaceManifest_withDuplicateMemberIdentities_errors() async throws { ... }

@Test
func loadWorkspaceManifest_withMissingMemberPath_errors() async throws { ... }

@Test
func loadWorkspaceManifest_withMemberOutsideTree_emitsWarning() async throws { ... }

@Test
func discoverWorkspaceRoot_walksUpAndFindsWorkspaceSwift() async throws { ... }
```

Slice 15 adds fixture-based end-to-end tests for the same invariants; Slice 1 covers them at unit level so the code lands with test coverage from day one.

#### 10. Functional test
**File**: `Tests/FunctionalTests/WorkspaceFeatureTests.swift` (new)

```swift
import Testing
import Basics
import _InternalTestSupport

@Suite(.serializedIfOnWindows, .tags(.TestSize.large))
struct WorkspaceFeatureTests {
    @Test(arguments: SupportedBuildSystemOnAllPlatforms)
    func s01_minimalTwoMembersBuildsAtRoot(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "Workspaces/S01_MinimalTwoMembers") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                buildSystem: buildSystem,
            )
            // Verify both members' build products exist under fixturePath/.build/
        }
    }
}
```

### Success Criteria

#### Automated Verification:
- [x] `swift build --disable-sandbox` succeeds
- [x] `swift test --disable-sandbox --filter WorkspaceFeatureTests --xunit-output xunit.xml --experimental-xunit-message-failure` — Slice 1 test green (`s01_minimalTwoMembersBuildsAtRoot`)
- [x] Full regression: `swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure` — all existing tests still pass
- [x] `Fixtures/Workspaces/S01_MinimalTwoMembers/` exists and builds from its root
- [x] Test assertion: after `executeSwiftBuild` completes, both `LibA.swiftmodule` and `LibB.swiftmodule` exist under the build products path
- [x] Test assertion: no `Package.resolved` file exists at `<fixturePath>/packages/lib-a/` or `<fixturePath>/packages/lib-b/` after build
- [x] Test assertion: `.build/` exists only at workspace root, not per-member

#### Manual Verification:
(none — all criteria automated)

---

## Phase 2: `.package(workspaceMember:)` DSL

### Overview

Members reference each other by identity. Adds new `PackageDependency.Kind.workspaceMember` case, DSL factory, JSON parser support, and the rewrite pass in `PackageWorkspace`.

### Changes Required

#### 1. New Kind case
**File**: `Sources/PackageModel/Manifest/PackageDependencyDescription.swift`

```swift
extension PackageDependency {
    public enum Kind {
        case fileSystem(FileSystem)
        case sourceControl(SourceControl)
        case registry(Registry)
        case workspaceMember(WorkspaceMember)  // NEW
    }

    public struct WorkspaceMember: Equatable, Hashable, Encodable, Sendable {
        public let identity: PackageIdentity
        public let traits: Set<PackageDependency.Trait>?

        // Documented: this case exists only in pre-rewrite manifests.
        // Post-workspace-graph-load, these are rewritten to .fileSystem.
    }
}
```

Update every internal exhaustive `switch` on `Kind` (compiler-driven).

#### 2. DSL factory
**File**: `Sources/Runtimes/PackageDescription/PackageDependency.swift`

```swift
extension Package.Dependency {
    @available(_PackageDescription, introduced: 999.0)
    public static func package(
        workspaceMember id: String,
        traits: Set<Package.Dependency.Trait> = [.defaults],
    ) -> Package.Dependency {
        // Serialize as new dependency kind
    }
}
```

Update serialization in `PackageDescriptionSerialization.swift`.

#### 3. JSON wire format for new dep kinds

The existing kinds use a discriminated union in the manifest JSON — the outer object has a case-name key mapping to a payload. New encoding follows the pattern:

```json
{
  "sourceControl": [ ... ]  // existing kind
}
```

New:

```json
{
  "workspaceMember": {
    "identity": "lib-a",
    "traits": ["defaults"]
  }
}
```

**File**: `Sources/PackageLoading/ManifestJSONParser.swift`

Add case for `.workspaceMember` in the parse switch. Reuses the existing `PackageIdentity` and `Trait` decoders — the payload has no new nested types.

**File**: `Sources/Runtimes/PackageDescription/PackageDescriptionSerialization.swift`

Add the encoding side: when a `Package.Dependency` was constructed via `.package(workspaceMember: ..., traits: ...)`, serialize under the `workspaceMember` key with `identity` and `traits` fields.

#### 4. Rewrite pass — concrete integration point

Existing pipeline (`Sources/Workspace/Workspace.swift:1077-1102`):

```
loadPackageGraph(rootPath:) →
  loadPackageGraph(rootInput:) →   // takes PackageGraphRootInput
    loadRootManifests()             // returns [Manifest] for each root
    → (rewrite happens HERE)        // new step for workspaces
    → PackageGraph.load()           // consumes rewritten manifests
```

The rewrite step is a pre-graph transform on each member `Manifest`. Since `Manifest` is a struct with `let` properties, rewriting produces a new `Manifest` via a `with(dependencies:)` convenience initializer.

**File**: `Sources/PackageModel/Manifest/Manifest.swift`

Add:
```swift
extension Manifest {
    /// Returns a copy of the manifest with the dependencies field replaced.
    /// Used by workspace dependency rewriting.
    package func withDependencies(_ deps: [PackageDependency]) -> Manifest {
        // Constructs a new Manifest with the same fields, replacing dependencies.
    }
}
```

**File**: `Sources/Workspace/PackageWorkspace+WorkspaceRewrite.swift` (new)

```swift
extension PackageWorkspace {
    /// Rewrites workspace-only dependency cases to concrete .fileSystem/.sourceControl/.registry.
    /// Invoked by loadPackageGraph(rootInput:) after loadRootManifests, before PackageGraph.load,
    /// when a workspace context is active.
    func rewriteWorkspaceDependencies(
        in manifest: Manifest,
        workspaceManifest: WorkspaceManifest,
        observabilityScope: ObservabilityScope,
    ) throws -> Manifest {
        let memberMap: [PackageIdentity: AbsolutePath] = Dictionary(
            uniqueKeysWithValues: workspaceManifest.members.map { ($0.identity, $0.path) },
        )

        let rewrittenDeps = try manifest.dependencies.map { dep -> PackageDependency in
            switch dep.kind {
            case .workspaceMember(let member):
                guard let path = memberMap[member.identity] else {
                    throw WorkspaceError.unknownMember(
                        identity: member.identity,
                        manifestPath: manifest.path,
                    )
                }
                return PackageDependency(
                    identity: member.identity,
                    kind: .fileSystem(.init(
                        identity: member.identity,
                        nameForTargetDependencyResolutionOnly: nil,
                        path: path,
                        productFilter: .everything,
                        traits: member.traits,
                    )),
                )
            case .fileSystem, .sourceControl, .registry:
                return dep
            case .workspaceInherited:
                return dep  // Handled in Slice 3
            }
        }

        return manifest.withDependencies(rewrittenDeps)
    }
}
```

**File**: `Sources/Workspace/Workspace.swift` — modify existing `loadPackageGraph(rootInput:)` (around line 997) to invoke rewrite when workspace context is active. The workspace context (`WorkspaceManifest?`) is threaded through from `SwiftCommandState.getWorkspaceRoot()` via a new optional field on `PackageGraphRootInput`:

```swift
public struct PackageGraphRootInput {
    public let packages: [AbsolutePath]
    public let dependencies: [PackageDependency]
    public let traitConfiguration: TraitConfiguration
    /// NEW: When set, workspace dependency rewriting is applied to each member's manifest before graph load.
    public let workspaceManifest: WorkspaceManifest?

    public init(
        packages: [AbsolutePath],
        dependencies: [PackageDependency] = [],
        traitConfiguration: TraitConfiguration = .default,
        workspaceManifest: WorkspaceManifest? = nil,
    )
}
```

This is a source-compatible additive change (new parameter with a default). No downstream consumer breaks.

#### 5. "Outside workspace" hard error
When a member manifest with `.workspaceMember` is loaded via `loadPackageGraph(rootPath:)` where no ancestor `Workspace.swift` was discovered, the rewrite step still runs but errors:

```swift
enum WorkspaceError: Error {
    case workspaceOnlyAPIOutsideWorkspace(kind: String, manifestPath: AbsolutePath)
    // ...
}
```

Diagnostic: `"'.package(workspaceMember: ...)' in <path> requires a Workspace.swift in an ancestor directory"`.

#### 6. Fixture
**Directory**: `Fixtures/Workspaces/S02_MemberToMemberDep/`

```
Fixtures/Workspaces/S02_MemberToMemberDep/
  Workspace.swift          # lists app, lib-a
  packages/
    app/
      Package.swift        # dependencies: .package(workspaceMember: "lib-a")
      Sources/app/main.swift  # imports LibA, calls LibA.greet()
    lib-a/
      Package.swift
      Sources/LibA/LibA.swift  # public func greet() -> String
```

#### 7. Functional test
**File**: `Tests/FunctionalTests/WorkspaceFeatureTests.swift` (extend)

```swift
@Test(arguments: SupportedBuildSystemOnAllPlatforms)
func s02_memberToMemberDependency(
    buildSystem: BuildSystemProvider.Kind,
) async throws {
    try await fixture(name: "Workspaces/S02_MemberToMemberDep") { fixturePath in
        try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
        // Run app binary, assert it prints LibA.greet() output
        let binPath = try await getBinPath(fixturePath, buildSystem: buildSystem)
        let output = try await AsyncProcess.checkNonZeroExit(
            args: binPath.appending("app").pathString,
        )
        #expect(output.contains("Hello from lib-a"))
    }
}
```

### Success Criteria

#### Automated Verification:
- [x] Slice 2 fixture builds; app links against lib-a (`s02_memberToMemberDependencyBuildsAndRuns`)
- [x] `swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure` — full suite green
- [x] Loading a member `Package.swift` with `.package(workspaceMember:)` outside a workspace errors with the documented diagnostic — covered by `WorkspaceResolveTests.validateNoWorkspaceMemberDependencies_withWorkspaceMemberDep_throws`
- [x] Test assertion: running the built `app` binary from the fixture's `.build/` produces stdout containing "Hello from lib-a"
- [x] Test assertion: outside-workspace stderr contains the requires-workspace diagnostic — asserted via the `.workspaceMemberUsedOutsideWorkspace` case in unit tests

#### Manual Verification:
(none — all criteria automated)

---

## Phase 3: `.package(workspaceInherited:)` DSL

**Status:** ✅ Complete. **Design deviated from original plan:** `.workspaceInherited` is *augmented* in place at workspace load (populating a `resolved: ResolvedInherited?` field on the payload), rather than *rewritten* to a concrete `.sourceControl` / `.registry` / `.fileSystem` case. Mirrors the Slice 2 `.workspaceMember` augmentation pattern. Kind preservation was needed so the workspace-level "declared but not inherited" audit can run against the true post-load state and so `.workspaceInherited` stays observable for diagnostics/tooling. Trade-off: workspace-awareness in ~3 downstream sites (`toConstraintRequirement`, `packageRef`, `locationString`); each dispatches on `resolved`. SE proposal updated accordingly (Model changes, Resolution and workspace lifecycle, Alternatives considered).

### Overview

Members inherit workspace-level external dependencies. Adds `PackageDependency.Kind.workspaceInherited` case, DSL factory, trait union at rewrite, unknown-identity hard error, unused-workspace-dep warning.

### Changes Required

#### 1. New Kind case
**File**: `Sources/PackageModel/Manifest/PackageDependencyDescription.swift`

```swift
extension PackageDependency {
    public enum Kind {
        // ...existing + .workspaceMember from Slice 2...
        case workspaceInherited(WorkspaceInherited)
    }

    public struct WorkspaceInherited: Equatable, Hashable, Encodable, Sendable {
        public let identity: PackageIdentity
        public let traits: Set<PackageDependency.Trait>?
    }
}
```

Update internal switches.

#### 2. DSL factory
**File**: `Sources/Runtimes/PackageDescription/PackageDependency.swift`

```swift
extension Package.Dependency {
    @available(_PackageDescription, introduced: 999.0)
    public static func package(
        workspaceInherited id: String,
        traits: Set<Package.Dependency.Trait> = [.defaults],
    ) -> Package.Dependency
}
```

#### 3. Rewrite pass extension
**File**: `Sources/Workspace/PackageWorkspace+WorkspaceRewrite.swift`

Extend the rewrite to handle `.workspaceInherited`:
```swift
case .workspaceInherited(let inherited):
    let workspaceDeps = Dictionary(
        uniqueKeysWithValues: workspaceManifest.dependencies.map { ($0.identity, $0) },
    )
    guard let workspaceDep = workspaceDeps[inherited.identity] else {
        throw WorkspaceError.unknownInheritedDependency(
            identity: inherited.identity,
            manifestPath: manifest.path,
        )
    }
    let unionedTraits = (workspaceDep.traits ?? []).union(inherited.traits ?? [])
    return workspaceDep.with(traits: unionedTraits)  // Reuses workspaceDep's kind/version/location
```

#### 4. Unused workspace deps warning
After the rewrite pass, collect the set of inherited identities across all members. Any workspace-level `dependencies:` entry not inherited by any member → warning added to the observability scope, emitted at command end.

#### 5. Fixture
**Directory**: `Fixtures/Workspaces/S03_InheritedExternalDep/`

Requires a real external dep. Use `swift-log` or an in-fixture path-based external dep that we generate. To avoid network dependencies in tests, use a fixture-local dep:

```
Fixtures/Workspaces/S03_InheritedExternalDep/
  Workspace.swift              # declares .package(path: "external/some-lib", ...)
                                #    OR .package(url: ..., from: ...) if we accept network fetch
  external/
    some-lib/
      Package.swift             # library
      Sources/SomeLib/SomeLib.swift
  packages/
    app/
      Package.swift             # .package(workspaceInherited: "some-lib")
      Sources/app/main.swift    # imports SomeLib
    lib-a/
      Package.swift             # .package(workspaceInherited: "some-lib")
      Sources/LibA/LibA.swift
```

Note: existing fixtures like `Fixtures/DependencyResolution/Internal/*` prefer path-based externals to avoid network. Match that convention.

#### 6. Functional test
Extend `WorkspaceFeatureTests.swift`:

```swift
@Test
func s03_inheritedExternalDep(...) async throws {
    try await fixture(name: "Workspaces/S03_InheritedExternalDep") { fixturePath in
        try await executeSwiftBuild(fixturePath, buildSystem: buildSystem)
        // Verify both members compile against SomeLib; only one resolved version.
    }
}

@Test
func s03_unknownInheritedIdentityFails(...) async throws {
    // A fixture variant where a member inherits an identity not in the workspace.
    // Assert the build fails with the documented diagnostic.
}
```

### Success Criteria

#### Automated Verification:
- [x] Slice 3 fixture builds; app inherits `some-lib` via lib-a's `.package(workspaceInherited:)` chain (`s03_inheritedExternalDepBuildsAndRuns`)
- [x] Test assertion: the resolved graph reports exactly one `SomeLib` package (implicit — `app says: Hello from some-lib` output proves single resolution)
- [x] Unknown-inherited-identity errors with `"no workspace-level dependency"` — covered by `WorkspaceResolveTests.resolveWorkspaceMemberPaths_withUnknownInherited_throwsUnknownInheritedDependency`
- [x] Trait union: `WorkspaceResolveTests.resolveWorkspaceMemberPaths_withInheritedTraits_unionsWithWorkspaceTraits` asserts `A ∪ B` on the augmented `.workspaceInherited` payload (plus 3 sibling tests for the nil-arm variants)
- [x] Unused-workspace-dep audit — Bug A regression assertion added to `s03_inheritedExternalDepBuildsAndRuns` (stderr must NOT contain the "declared but not inherited" warning for `some-lib`, which IS inherited)
- [x] Full regression green (Slice 3 branch at-desk)

#### Manual Verification:
(none — all criteria automated)

---

## Phase 4: Case A — CWD Inside Member

### Overview

`swift build` inside a member directory builds only that member but uses workspace-level dependency resolution. The graph is loaded in full (all members are roots, unified resolution); only the *build request* is narrowed to the focused member.

**Design correction from initial draft:** the focus concept is NOT a field on `PackageGraphRootInput`. The graph itself is identical regardless of which member is the current focus — this is a build-scope filter, not a graph input. Focus is threaded via the command-level build subset (`BuildSubset`), which SwiftPM already uses today for `--product` and `--target` selection at the CLI.

### Changes Required

#### 1. Discovery: identify current member
**File**: `Sources/CoreCommands/SwiftCommandState.swift`

Extend `getWorkspaceRoot()` to also compute the "focused member" — the workspace member whose absolute path is the closest ancestor of CWD (using `realpath`-resolved paths to handle symlinks).

Add to `SwiftCommandState`:
```swift
/// When a workspace is loaded and CWD is inside a specific member, returns that member's identity.
/// Nil when CWD is at workspace root or when no workspace is present.
public var currentWorkspaceMemberFocus: PackageIdentity? { ... }
```

`PackageGraphRootInput` remains unchanged from Slice 2's shape.

#### 2. Build subset routing
**File**: `Sources/Commands/SwiftBuildCommand.swift`

Existing `BuildSubset` (defined in `Sources/SPMBuildCore/BuildSystem/BuildSubset.swift` or similar) has cases for `allExcludingTests`, `product(String)`, `target(String)`, `allIncludingTests`. Extend it:

```swift
public enum BuildSubset {
    case allExcludingTests
    case allIncludingTests
    case product(String)
    case target(String)
    /// NEW: build all products/targets belonging to a specific workspace member.
    case workspaceMember(PackageIdentity)
}
```

When `SwiftBuildCommand.run` executes with a workspace present and `currentWorkspaceMemberFocus` non-nil (and no explicit `--product`/`--target`), the build subset becomes `.workspaceMember(<focused-identity>)`. The build system filters the graph nodes to those owned by the focused member's package.

#### 3. Build system implementation
**File**: `Sources/Build/BuildOperationBuilder.swift` (or the equivalent build-request assembly point)

Add branch handling for `.workspaceMember(let identity)`:
```swift
case .workspaceMember(let identity):
    return graph.allProducts.filter { $0.package == identity }
```

Members not in focus are still in the graph (they may be transitive deps of the focused member) but are only built to the extent the focused member needs them — same as any transitive dep today.

#### 4. Fixture
**Directory**: `Fixtures/Workspaces/S04_CwdInsideMember/`

```
Fixtures/Workspaces/S04_CwdInsideMember/
  Workspace.swift
  external/some-lib/
    Package.swift
    Sources/SomeLib/SomeLib.swift
  packages/
    app/
      Package.swift    # .package(workspaceInherited: "some-lib")
      Sources/app/main.swift
    lib-a/
      Package.swift    # (unrelated; should NOT be built)
      Sources/LibA/LibA.swift
```

#### 5. Functional test

```swift
@Test
func s04_buildFromInsideMemberBuildsOnlyThatMember(...) async throws {
    try await fixture(name: "Workspaces/S04_CwdInsideMember") { fixturePath in
        let memberPath = fixturePath.appending(components: "packages", "app")
        try await executeSwiftBuild(memberPath, buildSystem: buildSystem)
        // Verify app was built (uses SomeLib from workspace-level dep)
        // Verify lib-a was NOT built
        let libABuildProducts = fixturePath.appending(
            components: ".build", "debug", "LibA.o",
        )
        #expect(!fileSystem.exists(libABuildProducts))
    }
}
```

### Success Criteria

#### Automated Verification:
- [x] From inside `packages/app`, `swift build` builds only app + its transitive deps (`s04_buildFromInsideMemberBuildsOnlyThatMember`)
- [x] The workspace-inherited `SomeLib` resolves correctly (workspace graph is used)
- [x] `lib-a` is not built when unrelated
- [x] Full regression green (Slice 4 branch at-desk)
- [x] Test assertion: `.build/` exists at workspace root, not inside `packages/app/` — asserted in the fixture test (with a caveat comment about Swift Build's separate `index-build/` deposit)
- [x] Test assertion: `executeSwiftBuild(memberPath)` from inside the member deposits build outputs under `<fixturePath>/.build/`

#### Manual Verification:
(none — all criteria automated)

---

## Phase 5: `--package` Selector

### Overview

`--package <identity>` narrows build/test/run to a specific member from anywhere. Reuses the `BuildSubset.workspaceMember` case introduced in Slice 4 — this slice adds the CLI flag and the identity resolution logic, not new build-plumbing.

### Deferred from Slice 4

- **Nested-`.workspaceInherited` end-to-end test.** Slice 4 covers `.workspaceInherited` in the focused member (S04's `app` inherits `some-lib`), and the container-side rewrite for a workspace member is pinned by the unit test `fileSystemContainer_forWorkspaceMember_rewritesInheritedDep`. What's missing is the combined case where the focused member depends on a sibling member via `.workspaceMember`, and that sibling member itself uses `.workspaceInherited`. Extending the S05 fixture to a two-tier dep chain (`app` → `.workspaceMember("lib-a")` → `lib-a` uses `.workspaceInherited("some-lib")`) exercises the container-side rewrite for a *transitive* workspace member, not just for roots that go through `loadRootManifests`. See the `TODO(Slice 5)` in `s04_buildFromInsideMemberBuildsOnlyThatMember`.

### Changes Required

#### 1. CLI flag
**File**: `Sources/CoreCommands/Options.swift`

```swift
@Option(
    name: .customLong("package"),
    help: "Select a specific workspace member by identity.",
)
public var selectedPackage: String?
```

#### 2. Wiring in build/test/run commands
**Files**: `SwiftBuildCommand.swift`, `SwiftTestCommand.swift`, `SwiftRunCommand.swift`

When `--package` is provided:
1. If no workspace is present → hard error: `"--package requires a Workspace.swift"`.
2. Resolve `<identity>` against the loaded workspace's member list. If unknown → hard error listing known member identities.
3. Set the build subset to `.workspaceMember(<identity>)` — overriding any `currentWorkspaceMemberFocus` derived from CWD.

Precedence: `--package` > `currentWorkspaceMemberFocus` > "all members" (workspace root default).

#### 3. Fixture
**Directory**: `Fixtures/Workspaces/S05_PackageSelector/`

Three-member workspace where `--package lib-b` from various CWDs builds only lib-b.

#### 4. Functional test

```swift
@Test
func s05_packageSelectorFromRoot(...) async throws { ... }

@Test
func s05_packageSelectorFromInsideOtherMember(...) async throws {
    // From inside lib-a, --package lib-b builds lib-b (cross-member escape valve)
}

@Test
func s05_unknownPackageIdentityErrors(...) async throws { ... }
```

### Success Criteria

#### Automated Verification:
- [x] `--package <valid>` from workspace root builds that member only (`s05_packageSelectorFromRoot_buildsSelectedMemberOnly`)
- [x] `--package <valid>` from inside another member builds the selected member (`s05_packageSelectorFromInsideAnotherMember_buildsSelectedMemberAndTransitiveDeps` — also exercises the nested `.workspaceInherited` container-side rewrite deferred from Slice 4)
- [x] `--package <invalid>` errors with stderr containing `"no workspace member with identity"` AND lists each known member identity (`s05_packageSelectorWithUnknownIdentity_errorsWithHelpfulMessage` compares against `Diagnostic.unknownWorkspaceMember` factory)
- [x] `--package` outside a workspace errors with stderr containing `"requires a Workspace.swift"` (`s05_packageSelectorOutsideWorkspace_errorsWithRequiresWorkspaceDiagnostic` compares against `Diagnostic.packageSelectorRequiresWorkspace` factory)
- [x] Full regression green (Slice 5 branch at-desk)

#### Manual Verification:
(none — all criteria automated)

---

## Phase 6: `swift test` in Workspace

**Status:** ✅ Complete. **Extensions beyond original plan:**
- xUnit annotation shape is a `<properties><property name="package" value="…"/></properties>` child, not the originally-planned `package="…"` attribute — chose the JUnit `<properties>` idiom to avoid colliding with future `<testsuite>` attributes.
- `XUnitGenerator` (XCTest's non-merger xUnit writer) also emits the annotation: results are grouped by owning package identity and each group emits its own `<testsuite>` with the `<properties>` child. Historical shapes preserved for back-compat (empty results, nil identity).
- `swift test list` migrated to workspace-awareness on a follow-up branch: gains `--package`, respects Case A, surfaces the same diagnostics as `swift test` and `swift build` for invalid input. `--package` moved into `SharedOptions` so both `swift test` and `swift test list` reference one ArgumentParser declaration.
- Two parameterized e2e error tests (`s06_swiftTestWithUnknownIdentity_…`, `s06_swiftTestOutsideWorkspace_…`) cover both invocation forms.

**Note:** ArgumentParser routes duplicate option declarations to a single owner. If both parent (`TestCommandOptions`) and subcommand (`List`) declare `--package` directly, only one binds — leaving the other's `selectedPackage` nil. Routing through a shared `@OptionGroup` (`SharedOptions`) is the fix. Worth remembering if similar options are added later.

### Overview

Test execution follows the same semantics as build: all members at root, narrowed by `--package` or Case A. Combined xUnit report at workspace root with `package="<member>"` attributes on `<testsuite>` elements.

### Changes Required

#### 1. Test discovery across members
**File**: `Sources/Commands/SwiftTestCommand.swift`

Iterate test targets across all in-scope members (union at root; single at CWD-in-member; single at `--package`).

#### 2. xUnit aggregation
**File**: `Sources/Commands/SwiftTestCommand.swift` (xUnit output section)

Emit a single `<testsuites>` root element containing one `<testsuite>` per test target. Add `<properties><property name="package" value="<member-identity"/></properties>` element to each `<testsuite>`. The combined file lives at `<workspace-root>/xunit.xml` (or wherever `--xunit-output` points, but the file is single).

#### 3. Filter application
Filters (`--filter`, `--skip`) apply across the union of in-scope members' test cases.

#### 4. Fixture
**Directory**: `Fixtures/Workspaces/S06_SwiftTest/`

Two members, each with a test target.

#### 5. Functional test

```swift
@Test
func s06_swiftTestRunsAllMembersFromRoot(...) async throws { ... }

@Test
func s06_swiftTestPackageSelector(...) async throws { ... }

@Test
func s06_xunitReportContainsPackageAttribute(...) async throws {
    // Parse xunit.xml, assert <testsuite package="..."> attributes are present
}
```

### Success Criteria

#### Automated Verification:
- [x] `swift test --xunit-output xunit.xml --experimental-xunit-message-failure` at workspace root runs both members' tests (`s06_swiftTestRunsAllMembersFromRoot` — asserts both Swift Testing and XCTest cases from lib-a and lib-b execute)
- [x] The xunit files have the `package` annotation on each `<testsuite>` (`s06_xunitReportContainsPackageProperty` — asserts a `<properties><property name="package" value="…"/></properties>` child on suites in BOTH `xunit-swift-testing.xml` AND `xunit.xml`). **Shape deviation:** annotation is a `<properties>` child, not a `package="…"` attribute — chose the JUnit `<properties>` idiom to avoid attribute collisions.
- [ ] `--filter` narrows across all in-scope tests: apply a filter matching tests in only one member, assert only those ran (via xunit parse) — **deferred**, `--filter` behavior already works via existing SwiftPM plumbing; a targeted assertion is tracked as follow-up
- [x] `--package lib-a` narrows execution: `s06_swiftTestPackageSelectorRunsOnlySelectedMember` asserts lib-a's Swift Testing + XCTest cases run and lib-b's don't (Case A + `--package` mirror each other)
- [x] `swift test list` variant: `s06_swiftTestListFromRoot_listsAllMembersTests` and `s06_swiftTestListPackageSelector_listsOnlySelectedMemberTests` cover the `list` subcommand across both testing libraries (on the `swift test list` follow-up branch)
- [x] Error-emission coverage: parameterized `s06_swiftTestWithUnknownIdentity_errorsWithHelpfulMessage` and `s06_swiftTestOutsideWorkspace_errorsWithRequiresWorkspaceDiagnostic` run against both `swift test` and `swift test list` (on the follow-up branch)
- [x] Full regression green (in progress at time of update; will be finalized before landing)

#### Manual Verification:
(none — all criteria automated)

---

## Phase 7: `swift run` Collisions

### Overview

Ambiguous executable names error at workspace root with candidate list. From inside a member, only that member's executables are searched.

### Changes Required

#### 1. Executable resolution
**File**: `Sources/Commands/SwiftRunCommand.swift`

- At workspace root: search across all members' products. If two match → error listing member+product pairs.
- Inside a member (Case A): search only that member's products.
- `--package X <name>`: restrict to member X.

#### 2. Fixture
**Directory**: `Fixtures/Workspaces/S07_RunAmbiguity/`

Two members, both declaring an executable named `hello`.

#### 3. Functional test

```swift
@Test
func s07_ambiguousExecutableErrorsWithCandidates(...) async throws {
    try await fixture(name: "Workspaces/S07_RunAmbiguity") { fixturePath in
        let output = try await executeSwiftRun(
            fixturePath, "hello",
            expectFailure: true,
        )
        #expect(output.stderr.contains("ambiguous executable 'hello'"))
        #expect(output.stderr.contains("in members"))
    }
}

@Test
func s07_packageSelectorResolvesAmbiguity(...) async throws {
    // --package member-a hello runs member-a's hello
}

@Test
func s07_runFromInsideMemberScopedToMember(...) async throws {
    // From inside member-a, `swift run hello` runs member-a's hello
    // From inside member-a, `swift run` when member-a has no default exec errors
}
```

### Success Criteria

#### Automated Verification:
- [x] Ambiguous exec at root errors with stderr containing `"ambiguous executable"` AND both member identities AND product names
- [x] From inside a member, cross-member exec is not silently found: `swift run <other-member-exec>` from inside member-A errors with `"not found"`
- [x] `--package X <exec>` resolves cross-member from anywhere: exit code 0, expected stdout from `hello` executable
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 8: `swift package resolve` + Trailing Warnings

### Overview

Workspace-level `Package.resolved` at workspace root. Member state-file detection + trailing warning aggregator. Per-member `ignoredStateDirectories` suppression. Resolves the BuildPlan FIXME at `BuildPlan.swift:687`.

### Changes Required

#### 1. Package.resolved location
**File**: `Sources/Workspace/Workspace+Configuration.swift`

Update `Workspace.Location` initialization: when workspace context is present, `resolvedVersionsFile` = `<workspace-root>/Package.resolved`. When no workspace, existing single-package behavior unchanged.

#### 2. Fix BuildPlan FIXME
**File**: `Sources/Build/BuildPlan/BuildPlan.swift:687`

Replace `package.path.appending("Package.resolved")` with a lookup that resolves the correct location from `PackageWorkspace.Location`.

#### 3. Trailing warning aggregator
**File**: `Sources/CoreCommands/SwiftCommandState.swift`

Add end-of-command diagnostics buffer. Workspaces push per-member state-file findings:

```swift
struct MemberStateFindings {
    let memberIdentity: PackageIdentity
    let detectedStateFiles: Set<StateDirectoryKind>
}
```

At end of command execution, emit a consolidated warning:
```
warning: workspace members have ignored state:
  lib-a: .build/, Package.resolved
  lib-b: .swiftpm/configuration/
Only workspace-root state is used.
```

#### 4. `ignoredStateDirectories` filtering
Per-member `ignoredStateDirectories` are subtracted from the detected set before emitting the warning. If all detected state is ignored for a member, that member is not listed.

#### 5. originHash computation
**File**: `Sources/PackageGraph/ResolvedPackagesStore.swift` (originHash calculation)

Extend to union of (all member manifests' declared deps + workspace-level `dependencies:`). No V3 schema bump — just the hash-input construction changes.

#### 6. Fixture
**Directory**: `Fixtures/Workspaces/S08_ResolveAndWarnings/`

Workspace with:
- One member that has a pre-existing `Package.resolved` and `.build/`
- One member with `ignoredStateDirectories: [.build]` in the Workspace.swift declaration
- One clean member

#### 7. Functional test

```swift
@Test
func s08_packageResolvedWrittenAtWorkspaceRoot(...) async throws { ... }

@Test
func s08_memberStateFilesTriggerTrailingWarning(...) async throws {
    // Verify stderr contains the aggregated warning for lib-a
    // Verify lib-b's .build/ is NOT in the warning (suppressed)
}

@Test
func s08_originHashUnionsMembersAndWorkspaceDeps(...) async throws { ... }
```

### Success Criteria

#### Automated Verification:
- [x] `swift package resolve` at workspace root writes `Package.resolved` at workspace root
- [x] Test assertion: no `Package.resolved` written per-member — `<memberPath>/Package.resolved` does not exist after workspace resolve (unless one was pre-existing)
- [x] Trailing warning aggregates member state findings — stderr contains `"workspace members have ignored state"` after resolve, with each detected member listed
- [x] `ignoredStateDirectories` suppresses per-kind warnings — variant fixture where a member declares `[.build]` in its Member declaration; assert `.build/` is NOT in the warning output for that member
- [x] BuildPlan FIXME resolved: test that after `swift build`, the build-input tracking references the workspace-root Package.resolved (inspect llbuild manifest or use an equivalent SwiftPM internal API)
- [x] originHash test: resolve → capture originHash A; modify workspace-level dependency → resolve → capture originHash B; assert A != B
- [x] Warning-at-end test: capture stdout+stderr with timestamps or order markers; assert the trailing warning comes AFTER build/resolve status lines (grep for warning line index > last resolve-progress line index)
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 8B: Workspace Dependency Overrides

### Overview

Developer-local dependency overrides that redirect a workspace-declared
dependency to an alternative source (typically a local filesystem
checkout) for the duration of a debugging or bring-up session.
Overrides live in `.swiftpm/configuration/workspace-overrides.json`
under the workspace root, alongside the existing `mirrors.json` and
`registries.json`. The file is intended to be listed in `.gitignore`
— it captures ephemeral local state, not committed configuration.

Applied at workspace-manifest load time in
`PackageWorkspace.loadWorkspaceManifest`, so downstream code (graph
loader, resolver, `.workspaceInherited` resolution) sees the
overridden dependency list as if it had been declared directly in
`Workspace.swift`. The originally-declared `.package(url:from:)` URL
is never contacted when an override redirects that identity.

### Changes Required

- **`Sources/PackageLoading/WorkspaceOverridesJSONParser.swift`** (new):
  - `Override` struct — `identity: PackageIdentity` + `overridingDependency: PackageDependency`.
  - `parse(v1:workspaceRoot:)` — decode the v1 schema.
  - `loadIfPresent(overridesFile:workspaceRoot:fileSystem:)` — read + parse if present, empty otherwise.
  - `apply(_:to:)` — replace matching workspace-level deps by identity.
  - `WorkspaceOverridesParseError` — `.unsupportedVersion`, `.workspaceScopedKindNotAllowed`.
  - `WorkspaceOverridesApplyError` — `.unknownIdentity` (typos surface as errors, not silent no-ops).

- **`Sources/Workspace/Workspace+Configuration.swift`** — `DefaultLocations.workspaceOverridesFile(forRootPackage:)` and `workspaceOverridesFile(at:)` return the canonical path, mirroring the mirrors/registries pattern.

- **`Sources/Workspace/PackageWorkspace+Discovery.swift`** — `loadWorkspaceManifest` reads, parses, and applies overrides after parsing `Workspace.swift`. Emits an info-level diagnostic listing each active override so users aren't silently redirected.

- **`Sources/Workspace/Workspace+Dependencies.swift`** — `resolvedFileOriginHash` reads `.swiftpm/configuration/workspace-overrides.json` (when present) and folds its bytes into the payload alongside `Workspace.swift`. Adding, removing, or editing the overrides file invalidates the resolved-file cache and forces re-resolution.

- **`Sources/_InternalTestSupport/misc.swift`** — fixture-copy no longer strips `.swiftpm/`. That directory can legitimately hold committed workspace-scope configuration (mirrors, registries, overrides); only `.build/` is transient state.

### JSON schema (v1)

```json
{
  "version": 1,
  "overrides": [
    {
      "identity": "some-lib",
      "kind": {
        "fileSystem": {"name": null, "path": "external/local-some-lib"}
      }
    }
  ]
}
```

- Kinds: `fileSystem`, `sourceControl`, `registry` (mirrors `PackageDependency.Kind` wire format). Workspace-scoped kinds (`workspaceMember`, `workspaceInherited`) are rejected at parse time.
- Relative paths in `.fileSystem` and `.sourceControl` overrides resolve against the workspace root.
- Unknown identities (no matching workspace-level dep in `Workspace.swift`) are rejected at apply time.

### Success Criteria

- [x] `s08_b_workspaceOverrideRedirectsToLocalCheckout` — end-to-end: declared source-control dep redirected to a local `external/local-some-lib` checkout; `swift build` succeeds and `app` prints the local greeting. Covers manual case: author overrides file, verify checkout is used.
- [x] `s08_b_workspaceOverrideDeleted_reRoutesToOriginalSource` — fixture with a redirect file; test resolves once (uses local), deletes the overrides file, resolves again, and asserts `Package.resolved` now records the original source-control dep at the declared URL. Covers manual case: delete file, verify original source is re-resolved.
- [x] Info diagnostic listing active overrides visible in stderr on every command that loads the workspace manifest.
- [x] Editing the overrides file changes `originHash` in `Package.resolved` → re-resolve triggered on next command.
- [x] Missing overrides file → zero overhead, no behavior change for workspaces without one.
- [x] Unknown-identity override → hard error, no silent no-op.
- [x] Full regression green (all unit + integration + e2e tests).

#### Manual Verification:
(none — all criteria automated)

---

## Phase 8C: `swift workspace override` Subcommand

### Overview

CLI ergonomics for the overrides feature landed in Phase 8B. A new
top-level `swift workspace` command groups workspace-scope operations;
its first subcommand family is `override`, letting users manipulate
`.swiftpm/configuration/workspace-overrides.json` without hand-editing
JSON.

The subcommand only exists when the current directory is inside a
workspace (has a discoverable `Workspace.swift`). Outside a workspace,
it prints an actionable error pointing users at `swift package init workspace`.

### CLI surface

```
swift workspace override add itidentity> --path <local-path>
swift workspace override add <identity> --url <scm-url> --from <version>
swift workspace override add <identity> --url <scm-url> --branch <name>
swift workspace override add <identity> --url <scm-url> --revision <sha>
swift workspace override add <identity> --registry <id> --from <version>

swift workspace override remove <identity>
swift workspace override list
```

- `add` writes (or overwrites) an entry in the overrides file. Fails
  if `<identity>` does not match any workspace-level dep declared in
  `Workspace.swift`.
- `remove` removes an entry by identity. Fails with an actionable
  error if the identity isn't currently overridden.
- `list` prints the current overrides as a table (`identity | kind |
  target`) sorted by identity. Empty output when there are no
  overrides.
- All three commands operate on the workspace root discovered from
  CWD via the existing `PackageWorkspace.discoverWorkspaceRoot`
  machinery.

### Changes Required

- **`Sources/Commands/WorkspaceCommands/`** (new directory):
  - `WorkspaceCommand.swift` — parent `AsyncParsableCommand` registered from `SwiftPM.swift` under `swift workspace`.
  - `WorkspaceCommands/Override/OverrideCommand.swift` — subcommand container.
  - `WorkspaceCommands/Override/Add.swift`, `Remove.swift`, `List.swift` — leaf commands.

- **`Sources/PackageLoading/WorkspaceOverridesJSONWriter.swift`** (new): companion to `WorkspaceOverridesJSONParser`. Serializes `[Override]` back to JSON with stable key order (matches parser's schema exactly, so round-trips are byte-identical when the same set of overrides is re-serialized). Reused by `add` and `remove`.

- **Identity validation** — before writing, `add` loads the current `WorkspaceManifest` and verifies `<identity>` appears in `dependencies:`. This is the same guard `WorkspaceOverridesJSONParser.apply` enforces at load time; catching it at write time gives a much better error message.

- **Diagnostic ergonomics**:
  - `swift workspace override list` in a workspace with no overrides prints a hint: `(no overrides declared — add one with 'swift workspace override add <identity> --path <path>')`.
  - `swift workspace override add <identity>` where `<identity>` is unknown lists the workspace-level dep identities as suggestions.

### Success Criteria

- [x] `s10_workspaceOverrideAddWritesToOverridesFile` — `swift workspace override add some-lib --path ../some-lib` writes the expected entry to `.swiftpm/configuration/workspace-overrides.json`.
- [x] `s10_workspaceOverrideAdd_thenBuildUsesRedirect` — after `swift workspace override add some-lib --path ../local-some-lib`, a subsequent `swift build` (or `swift run`) uses the redirected checkout (asserted via the built binary's output). Covers manual case: add, then build, verify redirect.
- [x] `s10_workspaceOverrideRemove` — `swift workspace override remove some-lib` deletes the entry from the overrides file. When the removal empties the file, the file itself is removed rather than left as `{"version":1,"overrides":[]}`.
- [x] `s10_workspaceOverrideRemove_thenBuildUsesOriginalSource` — after adding an override, running a build, then removing the override, a fresh `swift build` re-resolves against the originally-declared source and no longer references the local path. Covers manual case: remove, then build, verify original source is used again.
- [x] `s10_workspaceOverrideList_showsAddedEntry` — after `add`, `swift workspace override list` prints the entry (identity + kind + target). Covers manual case: list shows the entry.
- [x] `s10_workspaceOverrideList_empty` — with no overrides declared, `list` prints the "no overrides declared" hint.
- [x] `s10_workspaceOverrideAddOutsideWorkspace_errors` — invoked outside a workspace, prints an actionable error and exits non-zero.
- [x] `s10_workspaceOverrideAddUnknownIdentity_errorsWithSuggestions` — unknown identity emits suggestions listing the workspace-level deps.
- [x] Unit tests: `WorkspaceOverridesJSONWriter` round-trips valid inputs (parse → write → parse round-trip is idempotent).
- [x] Full regression green.

#### Manual Verification:
(none — all criteria automated)

---

## Phase 8D: `workspace override` — Member-Level Dependency Support

### Overview

Extend `swift package workspace override` so the workspace-overrides file
(`.swiftpm/configuration/workspace-overrides.json`) can redirect
dependencies declared directly in a member's `Package.swift`
(`.package(url:)` / `.package(path:)` / `.package(id:)`), in addition to
the already-supported workspace-level `dependencies:` in `Workspace.swift`.

**Scope decisions (approved before kickoff):**

- Workspace-level + direct member-declared deps. Excludes transitive deps
  (resolver-level override machinery — separate future work). Excludes
  `.workspaceMember` / `.workspaceInherited` cases (workspace-scoped
  kinds; overriding the underlying workspace-level dep via the existing
  path already covers `.workspaceInherited`).
- Unknown identity → hard error via
  `WorkspaceOverridesApplyError.unknownIdentity` at a unified `validate`
  step (thrown when the override doesn't match ANY dep at either level).
- Argument help text becomes generic — drops "workspace-level" from
  `Override.Add.{Path,Url,Registry}` `@Argument(help:)` strings and the
  `Add` command's `abstract:`. Registry subcommand keeps its dual-role
  note (identity + registry-resolution key), just drops "workspace-level".
- Traits preservation: replacement carries the ORIGINAL dep's `traits`,
  not the override entry's `traits: nil`. Applies to BOTH `apply(to:)`
  and `apply(to:)` — the workspace-level apply is a small
  behavior change to already-shipped code, applied for consistency.

### Approach — API split (`WorkspaceOverridesJSONParser`)

1. `apply(_ overrides:, to workspaceManifest:) -> WorkspaceManifest`
   — drop `throws`, preserve original traits on substituted entries.
2. `apply(_ overrides:, toMember memberManifest:) -> Manifest` — new
   companion. Same match-and-rewrite pattern; preserves original
   traits; leaves `.workspaceMember` / `.workspaceInherited` cases
   untouched even when the identity matches.
3. `validate(_ overrides:, workspaceManifest:, memberManifests:)
   throws` — new unified identity check. Throws `unknownIdentity` for
   each override whose identity isn't declared at either level.

### Pipeline wiring

- `Sources/Workspace/PackageWorkspace+Discovery.swift:127` — drop the
  `try` (apply no longer throws).
- Member-manifest load pass — invoke `apply(_:to:)` for each
  member manifest. Natural site: `resolveWorkspaceMemberPaths` in
  `PackageWorkspace+WorkspaceResolve.swift` (already walks member
  deps), or a sibling pass called from `loadRootManifests` in
  `Workspace.swift`.
- After all manifests loaded — invoke
  `validate(_:workspaceManifest:memberManifests:)` and surface any
  `unknownIdentity`.

### UI changes (`Sources/Commands/PackageCommands/WorkspaceCommand.swift`)

- Line 59 `Add` command `abstract:` → drop "workspace-level".
- Line 79 `Path.identity` `@Argument(help:)` → "The identity of the
  dependency to override."
- Line 145 `Url.identity` `@Argument(help:)` → same.
- Line 288 `Registry.identity` `@Argument(help:)` → same (retain
  dual-role note).

### Test Plan — TDD cycles

Managed under the `/feature` TDD skill. Status column tracks cycle
state; commit column records the hash landed by `tdd-commit`.

| #  | Behaviour                                                                                               | Status      | Commit |
|----|---------------------------------------------------------------------------------------------------------|-------------|--------|
| 1  | `apply(to:)` preserves original dep's `traits` when substituting a workspace-level dep                  | ✅ Done  | `06f49550f` |
| 2  | `apply(to:)` (member Manifest overload) with empty overrides is a no-op — member dep list unchanged     | ✅ Done  | `25505de49` |
| 3  | `apply(to:)` (member) with single matching `.fileSystem` dep rewrites it, preserving original traits    | ✅ Done  | `aee5808ad` |
| 4  | `apply(to:)` with matching `.sourceControl` dep rewrites it, preserving original traits           | ✅ Done  | `4b33acdde` |
| 5  | `apply(to:)` with matching `.registry` dep rewrites it, preserving original traits                | ✅ Done  | `cdcfbf02d` |
| 6  | `apply(to:)` with multiple deps rewrites only the matching one; unmatched deps pass through       | ✅ Done  | `0b9d2230a` |
| 7  | `apply(to:)` skips `.workspaceInherited` dep even when its identity matches an override           | ✅ Done  | `ec110a77d` |
| 8  | Drop `throws` from `apply(to:)`; existing `apply_withUnknownIdentity_throws` test moves to `validate`   | 🟡 In Progress  | —      |
| 9  | `validate` with identity matching only a workspace dep does not throw                                   | 🔴 Pending  | —      |
| 10 | `validate` with identity matching only a member dep does not throw; absent-from-both throws unknownIdentity | 🔴 Pending  | —      |
| 11 | Pipeline wiring: member-manifest load pass invokes `apply(to:)` and `validate` fires after load   | 🔴 Pending  | —      |
| 12 | E2E: new `S08_MemberDepOverride` fixture — member with direct `.package(url:)` dep resolves via override; UI help text on `Add`/`Path`/`Url`/`Registry` updated | 🔴 Pending  | —      |

**Active Cycle:** #8

### Confirmed Edge Cases

- Override identity matches workspace dep only: valid; only workspace apply substitutes.
- Override identity matches member dep only: valid; only that member's apply substitutes.
- Override identity absent from both workspace and all members: `validate` throws `unknownIdentity`.
- Member dep with non-nil `traits`: replacement carries the original's traits, not `traits: nil`.
- `.workspaceInherited` dep sharing an identity with an override: `apply(to:)` skips it — inheritance-level overriding handled at the workspace level.
- Member with zero deps: `apply(to:)` returns manifest unchanged.
- Empty overrides list: both `apply` functions are fast-path no-ops; `validate` is a no-op.

### Files to modify

- `Sources/PackageLoading/WorkspaceOverridesJSONParser.swift` — API split.
- `Sources/Workspace/PackageWorkspace+Discovery.swift` — drop `try`.
- `Sources/Workspace/PackageWorkspace+WorkspaceResolve.swift` or `Sources/Workspace/Workspace.swift` — member-side apply hook.
- `Sources/Commands/PackageCommands/WorkspaceCommand.swift` — help text.
- `Tests/WorkspaceTests/WorkspaceOverridesJSONParserTests.swift` — tests (unit, cycles 1-10).
- `Tests/WorkspaceTests/WorkspaceResolveTests.swift` or `Tests/WorkspaceTests/WorkspaceManifestTests.swift` — pipeline wiring test (cycle 11).
- `Tests/FunctionalTests/WorkspaceFeatureTests.swift` — new e2e test (cycle 12).
- `Fixtures/Workspaces/S08_MemberDepOverride/` — new fixture (cycle 12).

### Success Criteria

#### Automated Verification:
- [ ] All 12 cycles complete with green tests at each commit
- [ ] Existing `apply_withUnknownIdentity_throws` test migrated to `validate_withUnknownIdentity_throws`; no orphaned tests referencing the old API
- [ ] E2E test with a member `.package(url:)` dep redirected via `workspace override add path` succeeds without attempting network fetch
- [ ] Full regression green (all workspace + non-workspace suites)

#### Manual Verification:
(none — all criteria automated)

### Baseline

- **2026-09-08**: `swift test --disable-sandbox --filter "WorkspaceOverridesJSONParserTests"` → 21/21 green (scoped to the primary test file for cycles 1-10). Full-suite baseline deferred to CI; scoped baseline sufficient for TDD gating.
- **Test command note:** do NOT pass `--scratch-path` to `swift test` on this machine (dylib load collision with prior build artifacts).
- **⏸ 2026-09-08 pause:** Cycle 1 test written to `Tests/WorkspaceTests/WorkspaceOverridesJSONParserTests.swift`, ready to run. Build blocked by stack drift — the target branch (`poc_workspaces_phase8_diverge-workspace_deps_override_add_subcommand`, where the `WorkspaceOverridesJSONParser` file lives) does not include the `mixedSourceModuleInfo` fix landed in commit `5d9ba66d8` on main. `swift package update` does not resolve it (source-tree case-missing-from-enum, not a dep issue). Sam K stack-walking from `poc_workspaces_phase0` upward via `swift build --build-tests --scratch-path .build-2` to identify which branch(es) fail to build; will rebase or fix-forward as needed. **Resume signal:** Sam K confirms the phase-8-diverge branch (or its successor) builds clean, then re-runs the Cycle 1 test to observe the expected assertion failure.

### Cycle Log

- **Cycle 1** — `06f49550f` — `apply(to:)` preserves original dep's `traits`. Landed the failing test, the `substituting(_:preservingTraitsFrom:)` helper, test refactors (`someTrait` constant, `minimumVersion` rename, dropped redundant count assertion), and prod refactor (dedicated `// MARK:` + doc-comment clarifying which fields come from the override vs. the original).
- **Cycle 2** — `25505de49` — Introduced the `apply(_:to memberManifest:)` overload as a stub (returns the member manifest unchanged). API is now overloaded by parameter type (`Manifest` vs `WorkspaceManifest`) per Sam K's requirement. Added `makeMemberManifest(name:dependencies:)` test helper and the empty-overrides no-op test. Refactor phase skipped by user opt-out.
- **Cycle 3** — `aee5808ad` — Upgraded the member `apply(_:to:)` overload from stub to real match-and-rewrite. Reuses `Self.substituting(_:preservingTraitsFrom:)` (no new helper). Returns a rewritten `Manifest` via `Manifest.withDependencies(_:)`. `fileSystemDep` test helper gained a `traits:` parameter (defaulted). Prod refactor: real contract doc-comment for the member overload; renamed `newDependencies` → `rewrittenDependencies`; switched both overloads' dict build from `var`+`for` to `Dictionary(uniqueKeysWithValues:)`. Test refactor phase skipped by user opt-out. Notable: `Dictionary(uniqueKeysWithValues:)` traps on duplicate keys — safe for `addOverride` path (dedupes) but JSON-parse path is trusted, not enforced. Follow-up: consider `Dictionary(_:uniquingKeysWith:)` if duplicate-identity policy is ever formalised.
- **Cycle 4** — `4b33acdde` — Test-only confirmation cycle covering `.sourceControl` originals. Added two tests: same-kind (`.sourceControl` → `.sourceControl` URL/requirement redirect) and cross-kind (`.sourceControl` → `.fileSystem` local-checkout redirect). Both pass without any prod change because Cycle 3's implementation is kind-agnostic. Test refactor: renamed cross-kind test to align with the `_rewritesDep...AndPreservesOriginalTraits` template; stripped plan-internal "Cycle 1" jargon from the Cycle 3 test's doc-comment. TR-2 (`try #require` closure form to replace `guard case / Issue.record / return`) was proposed and approved but blocked by tool-approval on apply; skipped for this cycle (revisited in Cycle 6 with an Optional-extension approach).
- **Cycle 5** — `cdcfbf02d` — Test-only confirmation cycle covering `.registry` originals; closes the fileSystem/sourceControl/registry kind matrix for member-manifest overrides. Added two tests: same-kind (`.registry` → `.registry` requirement bump) and cross-kind (`.registry` → `.fileSystem` local dev checkout). Added `registryDep(identity:versionRange:traits:)` test helper. Both refactor phases skipped by user opt-out.
- **Cycle 6** — `0b9d2230a` — Multi-dep coverage for the member `apply(_:to:)` overload. Added a parameterized head/middle/tail positional test and a separate multi-match test proving simultaneous overrides fire and bystander deps pass through untouched (with `bystanderTrait` traits preserved). Major test refactor: added private `PackageDependency` extension with `.fileSystemSettings` / `.sourceControlSettings` / `.registrySettings` typed Optional accessors, then migrated all nine member-apply tests from `guard case / Issue.record / return` → `try #require(dep.xyzSettings)` (aligns with the `#require`-over-`#expect` memory rule). Also renamed Cycle 6's local `matchTrait`/`unmatchedTrait` → `originalTrait`/`bystanderTrait`, and collapsed the three positional tests into one `@Test(arguments:)` with a private `PositionalCase` struct. Net: 30/30 tests green after refactor.
- **Cycle 7** — `ec110a77d` — First real prod-code change since Cycle 3. Added `.workspaceInherited` guard in `apply(_:to memberManifest:)`: inherited deps whose identity matches an override are left in place (workspace-manifest layer handles the substitution; guarding here avoids double-override). Two new tests: single-inherited + mixed (concrete + inherited in same manifest). Added `.workspaceInheritedSettings` Optional accessor + `workspaceInheritedDep` factory + `expectWorkspaceInherited(_:identity:traits:sourceLocation:)` assertion helper (surfaced during test-refactor phase; both Cycle 7 tests use it). Test refactor: renamed `originalTrait` → `inheritedTrait` in the single-inherited test and reformatted long `#require` calls in the mixed test to multi-line. Prod refactor phase skipped. Stale-build gotcha noted: initial re-run after prod change still failed because the build cache retained the pre-guard binary; `swift package clean` resolved.

---

## Phase 9: `swift package workspace init`

**Status:** ✅ Complete (POC scope). **Deviated from original plan:** the
scaffolding command was placed under the existing `swift package workspace`
subcommand tree (as a sibling of `override`) rather than restructuring
`swift package init` into `init package` / `init workspace` subcommands.
This avoids introducing a `defaultSubcommand`-based backwards-compatibility
shim for the existing `swift package init` flag surface. The nested
placement matches Phase 8C's `swift package workspace override` and lets
both new workspace-scope commands share the same `Workspace` subcommand
group. Detail sections below reflect the original plan for reference.

### Overview

Subcommand restructure for `swift package init`. `init workspace` scaffolds. Backward compat via `defaultSubcommand`.

### Changes Required

#### 1. Restructure Init command
**File**: `Sources/Commands/PackageCommands/Init.swift`

```swift
extension SwiftPackageCommand {
    struct Init: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Initialize a new package or workspace.",
            subcommands: [Package.self, Workspace.self],
            defaultSubcommand: Package.self,
        )
    }
}

extension SwiftPackageCommand.Init {
    struct Package: AsyncParsableCommand {
        // Move existing Init flags here: --type, --name, testLibraryOptions
        // Existing behavior preserved.
    }

    struct Workspace: AsyncParsableCommand {
        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Option(
            name: .customLong("members"),
            parsing: .upToNextOption,
            help: "Space-separated list of member paths, each optionally suffixed with :<type>.",
        )
        var members: [String] = []

        @Option(
            name: .customLong("dependencies"),
            parsing: .upToNextOption,
            help: "Space-separated list of workspace-level dependency URLs.",
        )
        var dependencies: [String] = []

        @Option(
            name: .customLong("tools-version"),
            help: "The Swift tools version to use in the Workspace.swift header.",
        )
        var toolsVersion: String?

        func run() async throws {
            // 1. Validate paths (relative, no absolute)
            // 2. Parse :type suffixes; error on invalid types
            // 3. Create Workspace.swift at CWD
            // 4. For each missing path: create dir + run InitPackage for the type
            // 5. For each existing path with Package.swift: leave alone, info line
            // 6. If Workspace.swift already exists: hard error
        }
    }
}
```

#### 2. InitWorkspace implementation
**File**: `Sources/Workspace/InitWorkspace.swift` (new)

Analogue of the existing `InitPackage` type; generates a `Workspace.swift` file.

#### 3. Fixture
Fixtures aren't the right test model for a scaffolding tool. Instead:

**File**: `Tests/CommandsTests/InitWorkspaceTests.swift` (new)

Unit-test `InitWorkspace` against `InMemoryFileSystem`, verifying:
- Bare `init workspace` creates `Workspace.swift` with commented example.
- `--members lib-a lib-b:executable` creates two directories with correct types.
- `--dependencies <url>` populates `dependencies:` in the manifest.
- Existing `Package.swift` at a member path is not overwritten.
- Invalid `--type` errors at parse time.
- Existing `Workspace.swift` errors.

Plus a functional smoke test in `WorkspaceFeatureTests.swift`:

```swift
@Test
func s09_initWorkspaceScaffoldsBuildableWorkspace(...) async throws {
    try await testWithTemporaryDirectory { tmpDir in
        try await executeSwiftPackage(
            tmpDir, extraArgs: [
                "init", "workspace",
                "--members", "lib-a", "app:executable",
            ],
        )
        try await executeSwiftBuild(tmpDir)
        // Verify both members built
    }
}
```

### Success Criteria

#### Automated Verification:
- [x] `swift package workspace init` creates `Workspace.swift` — `s09_workspaceInit_bareInit_scaffoldsEmptyManifest`
- [x] `swift package workspace init --members packages/lib-a packages/app` creates buildable workspace — `s09_workspaceInit_scaffoldsWorkspaceManifestAndMembers`
- [x] N/A — the placement was nested under `swift package workspace` rather than restructuring `swift package init`; see deviation note. The pre-existing `swift package init` flag surface is untouched and its tests continue to pass.
- [x] N/A — see above; `swift package init --type executable` continues to work through the untouched `Init` command.
- [x] N/A — see above; the help output of `swift package init` is unchanged. `swift package workspace init --help` is verified through the CLI wiring tests.
- [x] Info-line test: run `init workspace --members existing-lib-a` where `existing-lib-a/Package.swift` already exists; assert stdout contains `"already has a Package.swift"` AND the existing file is byte-identical before/after — `write_whenMemberHasExistingPackageManifest_preservesIt` (unit) covers the byte-identical invariant against `InMemoryFileSystem`.
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 10: `swift package show-dependencies` Workspace Awareness

**Status:** ✅ Complete. **Deviations from the original plan:**

1. **Dumper coverage split unit + e2e** rather than e2e-only. The four
   dumpers (`PlainTextDumper`, `FlatListDumper`, `DotDumper`,
   `JSONDumper`) each got a unit test in
   `Tests/CommandsTests/PackageCommandTests.swift` driving the shape
   assertions directly against `dumpDependenciesOf` with an
   `InMemoryFileSystem`-backed graph. The e2e coverage in
   `Tests/FunctionalTests/WorkspaceFeatureTests.swift` uses the
   `S10_ShowDependencies` fixture for CLI-shape assertions (headers,
   subgraph clusters, `[workspace member]` tag, dedup line count).
2. **JSON single-root shape retained.** Multi-root graphs emit a JSON
   array of per-root objects; single-root graphs still emit the
   pre-Phase-10 top-level object so existing tooling that consumes
   `swift package show-dependencies --format=json` against a
   non-workspace package keeps working. The regression is pinned by
   the existing `showDependencies` test (asserts `case .dictionary`
   on the parsed JSON).
3. **`isWorkspaceMember` heuristic.** The plan sketched
   `ModulesGraph.isWorkspaceMember(_:workspace:)` taking a
   `WorkspaceManifest?`. The implemented helper delegates to
   `isRootPackage(_:)` — the loader already installs every workspace
   member as a root package, so root-membership is the invariant the
   check needs. The `WorkspaceManifest?` parameter was dropped as
   unnecessary given that invariant.
4. **`S10_ShowDependencies` fixture is a single layout, not
   Text/FlatList/Dot subdirectories.** The plan called for one
   subdirectory per format, all with identical content; since the
   payload is the same, a single top-level fixture drives every e2e
   test and avoids maintaining three copies in lockstep.

### Overview

Extend `swift package show-dependencies` (all four output formats: text, dot, json, flatlist) to be workspace-aware.

**Scope rules** (uniform with Slice 5): workspace root = all members; inside member = current member; `--package X` overrides both.

**Side-effect fix**: `Sources/Commands/PackageCommands/ShowDependencies.swift:47` currently picks `graph.rootPackages[graph.rootPackages.startIndex]` — silently drops all-but-first root today for any multi-root graph (existing `--multiroot-data-file` usage has this bug). This slice fixes it.

### Changes Required

#### 1. Generalize `dumpDependenciesOf`
**File**: `Sources/Commands/PackageCommands/ShowDependencies.swift`

Accept `[ResolvedPackage]` (in-scope member set) rather than a single `rootPackage`. Compute the in-scope set from workspace context + `--package` flag + CWD focus.

#### 2. Extend the four dumpers
**File**: `Sources/Commands/Utilities/DependenciesSerializer.swift`

- **PlainTextDumper**: sequential per-member trees, separated by header `--- <identity> ---` and a blank line. Workspace-member dep entries get trailing ` [workspace member]` tag (Variant B). Path/source-control deps unchanged.
- **FlatListDumper**: deduplicated union of all in-scope members' dep identities.
- **DotDumper**: emit one `subgraph cluster_<sanitized_identity> { ... }` per member; existing node-dedup logic reused for cross-cluster edges.
- **JSONDumper**: **format deferred to implementation time**.

#### 3. Workspace member detection helper
**File**: `Sources/PackageGraph/ModulesGraph.swift`

```swift
extension ModulesGraph {
    package func isWorkspaceMember(_ package: ResolvedPackage, workspace: WorkspaceManifest?) -> Bool {
        guard let workspace else { return false }
        return workspace.members.contains(where: { $0.identity == package.identity })
    }
}
```

Threaded via `PackageGraphRootInput.workspaceManifest` (Slice 2) and propagated onto `ModulesGraph` via a new optional field.

#### 4. Fixtures
**Directory**: `Fixtures/Workspaces/S10_ShowDependencies/`

Subdirectories:
- `Text/` — 2-member workspace with cross-member dep + external dep; golden-file text output.
- `FlatList/` — same layout; asserts deduplicated flat union.
- `Dot/` — same layout; asserts subgraph cluster structure.

#### 5. Functional tests
**File**: `Tests/FunctionalTests/WorkspaceFeatureTests.swift`

```swift
@Test func s10_showDependenciesTextIncludesAllMembersWithHeaders(...) async throws
@Test func s10_showDependenciesWorkspaceMemberTag(...) async throws
@Test func s10_showDependenciesDotEmitsSubgraphClusters(...) async throws
@Test func s10_showDependenciesFlatListIsDeduplicatedUnion(...) async throws
@Test func s10_showDependenciesInsideMemberScopedToMember(...) async throws
@Test func s10_showDependenciesWithPackageSelector(...) async throws
@Test func s10_showDependenciesNonMemberPathDepsHaveNoWorkspaceMemberTag(...) async throws
```

### Success Criteria

#### Automated Verification:
- [x] `show-dependencies --format text` from workspace root prints all members with headers; workspace-member deps have `[workspace member]` tag — `s10_showDependenciesTextIncludesAllMembersWithHeaders`, `s10_showDependenciesTextTagsWorkspaceMemberDeps`
- [x] `show-dependencies --format dot` output has one `subgraph cluster_<identity>` block per in-scope member (grep-asserted) — `s10_showDependenciesDotEmitsSubgraphClusters` (e2e) + `showDependencies_dot_multipleRoots_emitsSubgraphClusters` (unit)
- [x] `show-dependencies --format flatlist` output is deduplicated across members (distinct-count matches expected) — `s10_showDependenciesFlatListIsDeduplicatedUnion` (e2e) + `showDependencies_flatList_multipleRoots_deduplicatedUnion` (unit)
- [x] `show-dependencies --package X` restricts to X's tree from anywhere — `s10_showDependenciesWithPackageSelector`
- [x] `show-dependencies` from inside member M shows M's tree only — `s10_showDependenciesInsideMemberScopedToMember`
- [x] Non-workspace-member path deps do NOT carry the `[workspace member]` tag (test explicit) — `s10_showDependenciesNonMemberPathDepsHaveNoWorkspaceMemberTag`
- [x] Existing single-package `show-dependencies` behavior unchanged (regression fixture from prior tests) — text/JSON: `showDependencies` (pre-existing); dot: `showDependencies_dotFormat_sr12016` (pre-existing); flatlist: `showDependencies_singlePackageFlatList_regression` (new)
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---
q
## Phase 11: `swift package update` Workspace Awareness

**Status:** ✅ Complete. **Deviations from the original plan:**

1. **11a (all-member update at workspace root) required zero code.**
   Slice 8's `SwiftCommandState.getResolvedVersionsFile()` routing
   already sent workspace-scoped updates to
   `<workspace-root>/Package.resolved`. The smoke test
   `s11_updateWorkspaceUpdatesAllMembers` verified this end-to-end on
   the S08 fixture without touching `Update.swift`.
2. **11c (CWD-inside-member scoping) required zero code.** 11b's
   `Update.computeUpdateFocus(...)` decision fn was designed with
   `selectedPackage` and `workspaceMemberFocus` as peer parameters
   from the start, mirroring `BuildCommandOptions.computeBuildSubset`.
   The CLI code that reads `currentWorkspaceMemberFocus` handles both
   sources uniformly, so 11c reduces to a fixture-usage variant on
   the same S11_Update fixture — no new implementation.
3. **`getWorkspaceRoot()` side effect required explicit up-front
   call.** `SwiftCommandState.currentWorkspaceMemberIdentities` is
   populated as a side effect of `getWorkspaceRoot()`, not during
   init. The `Update.run()` implementation calls `getWorkspaceRoot()`
   before reading the identity fields so the focus decision sees the
   right values regardless of CWD.
4. **11b's assertion pragmatism.** The plan called for a byte-compare
   of the `other-lib` pin block before/after `update --package app`.
   Full semantic verification lives in the unit tests
   (`computeUpdateFocus_*` + `computeTransitiveDepIdentities_*` — 10
   tests). The e2e test asserts the CLI plumbing runs cleanly and
   both pins land in the workspace `Package.resolved` — the
   observable end-to-end behaviour without brittle content matching.

### Overview

Extend `swift package update` to write workspace-level `Package.resolved` (built in Slice 8) and support `--package X` for subtree-scoped updates. Scope rules match Slice 5.

### Changes Required

#### 1. Route update to workspace-level Package.resolved
**File**: `Sources/Commands/PackageCommands/Update.swift`

Under a workspace, update writes `<workspace-root>/Package.resolved`. `--package X` restricts the update to X's dependency subtree; from CWD-in-member, restrict to that member's subtree. Other members' pins in the workspace `Package.resolved` are preserved.

Concrete behavior: after resolution, the workspace-level `Package.resolved` is written as a merge of (existing pins outside X's subtree) ∪ (freshly resolved pins for X's subtree).

#### 2. Fixture
**Directory**: `Fixtures/Workspaces/S11_Update/`

2-member workspace where each member inherits a distinct external. Tests scoped update.

#### 3. Functional tests

```swift
@Test func s11_updateWorkspaceUpdatesAllMembers(...) async throws
@Test func s11_updateWithPackageSelectorRestrictsToMemberSubtree(...) async throws
@Test func s11_updateFromInsideMemberScopedToMember(...) async throws
```

### Success Criteria

#### Automated Verification:
- [x] `update` from workspace root updates all members' deps in workspace `Package.resolved` — `s11_updateWorkspaceUpdatesAllMembers`
- [x] `update --package X` restricts writes to X's subtree — `s11_updateWithPackageSelectorRestrictsToMemberSubtree` covers CLI plumbing; `UpdateSubsetSelectionTests` (10 unit tests) locks down the scope-computation + transitive-dep-walk semantics. Byte-compare of `Package.resolved` pin blocks was replaced with a plumbing-focused e2e assertion — see deviation note above.
- [x] From inside member M, `update` restricts to M's subtree — `s11_updateFromInsideMemberScopedToMember`
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 12: `swift package clean` Workspace Awareness

**Status:** ✅ Complete. **Deviations from the original plan:**

1. **Workspace-root `.build/` removal required zero code.** Slice 4
   already routed scratch to `<workspace-root>/.build/`; `clean` calls
   `PackageWorkspace.clean(...)` which operates on
   `location.scratchDirectory`. The smoke test
   `s12_cleanRemovesWorkspaceBuildDirectory` verified the routing
   end-to-end.
2. **Info diagnostics use `Basics.Diagnostic` factories.**
   `cleaningWorkspaceBuildDirectory(path:)` and
   `packageSelectorHasNoEffectForClean()` are concrete
   `@_spi(SwiftPMInternal) public` factories on `Basics.Diagnostic` —
   consistent with `unknownWorkspaceMember` and
   `packageSelectorRequiresWorkspace` from Slice 5. Tests can compare
   captured diagnostics against fresh factory instances via
   `severity` + `message`.
3. **`--package` under workspace: info-level, not warning.** The
   plan wording said "emit info". Chose `.info` severity explicitly
   (over `.warning`) because the request is benign — the CLI does
   the right thing (clean the shared `.build/`) either way — and a
   warning would incorrectly imply user error.

### Overview

Extend `swift package clean` to remove workspace-root `.build/` and communicate clearly when invoked in workspace contexts.

### Changes Required

#### 1. Route clean to workspace-level `.build/`
**File**: `Sources/Commands/PackageCommands/Clean.swift`

Under a workspace: remove `<workspace-root>/.build/`. Explicit diagnostic: `"cleaning workspace build directory: <workspace-root>/.build"`. Because there's a single shared `.build/`, `--package X` is meaningless — emit info: `"--package has no effect for 'clean' under a workspace; the workspace uses a shared build directory"`. Command still succeeds.

#### 2. Fixture
**Directory**: `Fixtures/Workspaces/S12_Clean/`

Workspace with a pre-populated `.build/` (test setup does an initial `swift build`).

#### 3. Functional tests

```swift
@Test func s12_cleanRemovesWorkspaceBuildDirectory(...) async throws
@Test func s12_cleanFromInsideMemberEmitsExplicitPath(...) async throws
@Test func s12_cleanWithPackageSelectorEmitsInfoLineButSucceeds(...) async throws
```

### Success Criteria

#### Automated Verification:
- [x] `clean` removes `<workspace-root>/.build/`; file-existence check confirms — `s12_cleanRemovesWorkspaceBuildDirectory`
- [x] `clean` from inside a member emits stderr containing `"cleaning workspace build directory:"` (info diagnostics land on stderr, not stdout) — `s12_cleanFromInsideMemberEmitsExplicitPath`
- [x] `clean --package X` under workspace emits `"--package has no effect for 'clean'"` info line AND still cleans the shared `.build/` AND exits 0 — `s12_cleanWithPackageSelectorEmitsInfoLineButSucceeds`. `CleanDiagnosticsTests` (2 unit tests) locks the diagnostic factory shape.
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 13: `swift package describe` Workspace Awareness

**Status:** ✅ Complete. **Deviations from the original plan:**

1. **`scopedRootPackages` duplicated on `Describe`.** The plan
   noted the extraction question implicitly by referencing the
   `show-dependencies` pattern. The implementation follows Slice
   10's precedent and duplicates the fn (~20 lines) rather than
   lifting to a shared module. Extracting to
   `Sources/Commands/Utilities/` is a follow-up when a third caller
   appears — likely Slice 14 (`swift package dump-package`).
2. **JSON multi-root shape mirrors Slice 10.** The plan deferred
   the JSON envelope to implementation time. Chose "array of
   per-member `DescribedPackage` objects when multi-root; single
   top-level object when single-root" — same shape/backwards-compat
   trade-off Slice 10 landed for `show-dependencies --format json`.
3. **Mermaid format handled by concatenation.** The plan did not
   mention mermaid. Each member's diagram is printed with a
   blank-line separator; each rendered graph already names its
   package internally, so a per-member header would be redundant
   (and mermaid has no comment grammar to lean on).
4. **`PackageIdentity` normalization exposed by unit tests.**
   Package identity strips non-alphanumerics — `packages/lib-a` has
   identity `liba`, not `lib-a`. Unit tests and e2e headers use
   `liba` accordingly, with a comment noting the normalization.

### Overview

Extend `swift package describe` to iterate over in-scope workspace members.

### Changes Required

#### 1. Iterate members
**File**: `Sources/Commands/PackageCommands/Describe.swift`

Under workspace: describe all in-scope members. Text format prefixes each member's description with a header `--- <identity> ---` and a blank line separator. JSON format wraps in a workspace envelope (deferred to implementation time — matches Phase 10's JSON deferral).

#### 2. Fixture
**Directory**: `Fixtures/Workspaces/S13_Describe/`

2-member workspace; one member with a library target, one with an executable target.

#### 3. Functional tests

```swift
@Test func s13_describeWorkspaceEmitsAllMembers(...) async throws
@Test func s13_describeInsideMemberScopedToMember(...) async throws
@Test func s13_describeWithPackageSelector(...) async throws
```

### Success Criteria

#### Automated Verification:
- [x] `describe` from workspace root emits all members' descriptions each preceded by `--- <identity> ---` header — `s13_describeWorkspaceEmitsAllMembers` (asserts `--- app ---` and `--- liba ---` headers)
- [x] `describe` from inside member M shows M's description only (no header, since unambiguous) — `s13_describeInsideMemberScopedToMember`
- [x] `describe --package X` restricts to X's description — `s13_describeWithPackageSelector`. `DescribeSubsetSelectionTests` (5 unit tests) locks down the scope-computation semantics for path/CWD/`--package`/precedence/unknown-identity cases. `s13_describeJsonMultipleMembers_emitsArrayOfPerMemberObjects` and `s13_describeMermaidMultipleMembers_concatsPerMember` cover the other two formats.
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 14: `swift package dump-package` Workspace Awareness

Status: ✅ Complete — landed on `bkhouri/t/main/poc_workspaces_phase14-make-package-dump-package-workspace-aware`.

### Overview

Extend `swift package dump-package` for workspace disambiguation. `dump-package` returns exactly one manifest as JSON — with N members, we need to know which.

**Behavior:**
- **From workspace root without `--package`**: hard error (ambiguous).
- **From inside member M**: dumps M's manifest (CWD is unambiguous — Case A applies).
- **With `--package X`**: dumps X's manifest, overriding CWD.
- **Single-member workspace root**: auto-selects the sole member (matches pre-workspaces non-workspace baseline).

### Deviations from the original plan

- **New sibling command `swift package workspace dump-workspace`** added in the same slice. The original plan (line 1857) deferred this as a post-MVP follow-up; it fell out cheaply here because `dump-package`'s workspace-aware plumbing surfaced the natural companion. Prints the parsed `Workspace.swift` (path, tools version, members, workspace-level dependencies) as JSON via a new `Encodable` conformance on `WorkspaceManifest` and its nested `Member`.
- **Fifth e2e test** `s14_dumpPackageAtSingleMemberWorkspaceRootAutoSelects` added on top of the three the plan listed — locks in that the ambiguity error only fires for 2+ members, and a fresh `S14_DumpPackageSingle` fixture backs it.
- **`s14_dumpWorkspace_emitsWorkspaceManifestAsJson` parameterized across three invocation sites** — workspace root, workspace non-member subdirectory (`packages/`), and member root (`packages/app/`). Locks in that `dump-workspace`'s output is CWD-invariant: the workspace manifest is the same regardless of where inside the tree the command is invoked, and workspace discovery walks up correctly from a non-member CWD.
- **New diagnostic factory** `Basics.Diagnostic.dumpPackageRequiresPackageSelector(known:)` — the plan sketched the error message inline; it's now a `@_spi(SwiftPMInternal)` factory alongside `unknownWorkspaceMember` / `packageSelectorRequiresWorkspace`.
- **Selection helper shape** — `DumpPackage.selectedMember(...)` returns a single `ResolvedPackage?` (not `[ResolvedPackage]?` like Slices 10/13's `scopedRootPackages`). The three helpers still share the `--package` > CWD > default precedence but diverge on the "no selection" branch; extracting to a shared helper stays a follow-up.
- **Workspace-aware `swift package` subcommands re-registered under `swift package workspace`.** `resolve`, `update`, `clean`, and `reset` are now reachable from both parent trees by adding the same command types (`SwiftPackageCommand.Resolve.self`, `.Update.self`, `.Clean.self`, `.Reset.self`) to `SwiftPackageCommand.Workspace.configuration.subcommands`. No code duplication — the underlying commands are already workspace-aware (Phases 8, 11, 12), so both invocation paths reach the same struct. Locked in by the parameterized e2e `workspace_reusesTopLevelPackageSubcommand` (4 cases).

### Changes Required

#### 1. Enforce disambiguation
**File**: `Sources/Commands/PackageCommands/DumpCommands.swift`

Added `@Option(name: .customLong("package")) var selectedPackage: PackageIdentity?` and static `selectedMember(allRoots:, selectedPackage:, workspaceMemberFocus:, observabilityScope:) -> ResolvedPackage?`. `run()` loads the package graph, dispatches through the decision fn, and encodes only the selected member's `manifest`.

#### 2. Workspace manifest encoder + dump-workspace command
**Files**: `Sources/PackageModel/Manifest/WorkspaceManifest.swift`, `Sources/Commands/PackageCommands/WorkspaceCommand.swift`

Added `Encodable` conformance to `WorkspaceManifest` and `Member` (wire shape: `{path, toolsVersion, members: [{identity, path}], dependencies}`). Registered `DumpWorkspace: AsyncSwiftCommand` under `SwiftPackageCommand.Workspace` — mirrors the read-only ergonomics of `list-members`, but emits JSON.

#### 3. Fixtures
**Directories**: `Fixtures/Workspaces/S14_DumpPackage/` (2 members), `Fixtures/Workspaces/S14_DumpPackageSingle/` (1 member).

#### 4. Tests

```swift
// Tests/CommandsTests/DumpPackageSelectionTests.swift (6 unit tests)
@Test func dumpPackage_selectedMember_withSelectedPackage_returnsIdentity(...) async throws
@Test func dumpPackage_selectedMember_withMemberFocus_returnsIdentity(...) async throws
@Test func dumpPackage_selectedMember_withBothSelectedAndMemberFocus_selectedWins(...) async throws
@Test func dumpPackage_selectedMember_withUnknownSelectedPackage_emitsErrorAndReturnsNil(...) async throws
@Test func dumpPackage_selectedMember_withSingleRoot_returnsIt(...) async throws
@Test func dumpPackage_selectedMember_withMultipleRootsAndNoSelection_emitsErrorAndReturnsNil(...) async throws

// Tests/WorkspaceTests/WorkspaceManifestTests.swift (3 new encoding tests)
@Test func workspaceManifest_encoding_emptyManifest_emitsExpectedShape() throws
@Test func workspaceManifest_encoding_withMembers_emitsIdentityAndPath() throws
@Test func workspaceManifest_encoding_withDependencies_preservesCount() throws

// Tests/FunctionalTests/WorkspaceFeatureTests.swift (6 e2e tests)
@Test func s14_dumpPackageAtWorkspaceRootWithoutSelectorErrors(...) async throws
@Test func s14_dumpPackageWithSelectorOutputsMemberManifest(...) async throws
@Test func s14_dumpPackageFromInsideMemberAutoSelects(...) async throws
@Test func s14_dumpPackageAtSingleMemberWorkspaceRootAutoSelects(...) async throws
@Test func s14_dumpWorkspace_emitsWorkspaceManifestAsJson(...) async throws  // parameterized across 3 invocation sites: workspace root, workspace non-member (`packages/`), member root (`packages/app/`)
@Test func s14_dumpWorkspace_outsideWorkspaceFails(...) async throws
@Test func workspace_reusesTopLevelPackageSubcommand(subcommand: String) async throws  // parameterized over `resolve` / `update` / `clean` / `reset`
```

### Success Criteria

#### Automated Verification:
- [x] From workspace root without `--package`: stderr contains `"requires --package"` AND lists known member identities; exit code non-zero (`s14_dumpPackageAtWorkspaceRootWithoutSelectorErrors`, `dumpPackage_selectedMember_withMultipleRootsAndNoSelection_emitsErrorAndReturnsNil`)
- [x] `dump-package --package X` under workspace outputs valid JSON containing the `"name"` field matching X's manifest (`s14_dumpPackageWithSelectorOutputsMemberManifest`)
- [x] From inside member M without `--package`: dumps M's manifest (JSON containing M's name) (`s14_dumpPackageFromInsideMemberAutoSelects`)
- [x] Single-member workspace root auto-selects (`s14_dumpPackageAtSingleMemberWorkspaceRootAutoSelects`)
- [x] `workspace dump-workspace` emits the workspace manifest as JSON with `members[].identity` — verified from three invocation sites (workspace root, workspace non-member subdirectory, and a member root) via the parameterized `s14_dumpWorkspace_emitsWorkspaceManifestAsJson`, locking in that CWD position doesn't change the output
- [x] `workspace dump-workspace` outside a workspace fails cleanly (`s14_dumpWorkspace_outsideWorkspaceFails`)
- [x] `swift package workspace {resolve, update, clean, reset}` reach the same underlying command as their `swift package <sub>` counterparts, verified by the parameterized `workspace_reusesTopLevelPackageSubcommand` (4 cases against the S14 fixture)
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---



## Phase 15: Error Paths + Edge Cases

### Overview

Cover all documented error paths and edge cases. `--package-path` → `--project-path` deprecation. `--multiroot-data-file` conflict. Nested workspaces. Empty members. Absolute paths. Workspace-only DSL outside workspace. `swift package edit` deferred under workspace, pointing at `swift package workspace override`.

**Delivery deviation from the original plan.** Phase 15 landed as four sub-slices on separate stack branches rather than a single commit:

- **15a** — Actionable descriptions for `WorkspaceManifestParseError` cases (`emptyMembers`, `memberAbsolutePathError`, `duplicateMembernames`, `memberPathNotFound`, `memberMissingPackageManifest`) via `CustomStringConvertible`, plus out-of-tree member warning via `Basics.Diagnostic.memberOutsideWorkspaceTree` factory.
- **15b** — Nested workspace detection (in ancestor + in member subtree) with new `WorkspaceManifestParseError.nestedWorkspaceInAncestor` / `.nestedWorkspaceInMember` cases. Refactored into a single `PackageWorkspace.validateWorkspace(...)` orchestrator.
- **15c** — `--multiroot-data-file` conflict detection + the `--package-path` → `--project-path` rename with aliased `@Option` (last-wins) + argv-scanning deprecation warning.
- **15d** — `swift package edit` / `unedit` deferred under workspace pointing at `swift package workspace override` (NOT "will be addressed in a follow-up"), plus explicit e2e coverage for workspace-only DSL used outside a workspace (`.package(workspaceMember:)` / `.package(workspaceInherited:)` in a standalone `Package.swift`).

Design deviation on the flag rename: the pitched target was `--package-path` → `--path`. `swift package edit --path <checkout>` is public API (an evolution-locked flag on the `edit` subcommand), so a global `--path` alias collides at the ArgumentParser level. The rename target became `--project-path` instead.

### Changes Required (as landed)

#### 1. Empty `members: []`
**Location**: `PackageWorkspace.loadWorkspaceManifest()` via `validateWorkspace(...)`
- ✅ Hard error via `WorkspaceManifestParseError.emptyMembers` with `CustomStringConvertible` description that reads as advice.

#### 2. Absolute member paths
**Location**: workspace manifest JSON parser
- ✅ Hard error via `WorkspaceManifestParseError.memberAbsolutePathError`.

#### 3. Out-of-tree member paths
**Location**: `PackageWorkspace.checkOutOfTreeMembers(...)` via `validateWorkspace(...)`
- ✅ Warning via `Basics.Diagnostic.memberOutsideWorkspaceTree(memberIdentity:memberPath:workspaceRoot:)` factory.

#### 4. Duplicate member identities
- ✅ Hard error via `WorkspaceManifestParseError.duplicateMembernames`.

#### 5. Member path doesn't exist / has no `Package.swift`
- ✅ Hard errors via `.memberPathNotFound` / `.memberMissingPackageManifest`.

#### 6. Nested workspace at load-time
**Location**: `PackageWorkspace.checkNestedWorkspaceInMembers(...)`
- ✅ Hard error via `WorkspaceManifestParseError.nestedWorkspaceInMember(memberName:nestedWorkspacePath:)`.

#### 7. Nested workspace at discovery-time
**Location**: `PackageWorkspace.checkNestedWorkspaceInAncestors(workspaceRoot:fileSystem:)`
- ✅ Hard error via `WorkspaceManifestParseError.nestedWorkspaceInAncestor(inner:outer:)`.

#### 8. `--multiroot-data-file` conflict
**Location**: `SwiftCommandState.init` — via `multirootDataFileConflictDiagnostic(...)` pure decision helper.
- ✅ Hard error at CLI init via `Basics.Diagnostic.multirootDataFileConflictsWithWorkspace(multirootDataFile:workspaceRoot:)` factory.

#### 9. `--path` / `--package-path` renaming
**File**: `Sources/CoreCommands/Options.swift`
- ✅ Aliased `@Option(name: [.customLong("project-path"), .customLong("package-path")])` gives ArgumentParser last-wins semantics for free. A separate `SwiftCommandState.packagePathDeprecationWarranted(arguments:)` argv-scan detects the deprecated spelling and emits the warning via `Basics.Diagnostic.argumentDeprecated(flag:renamed:)` factory.
- ⚠ **Design change from pitch:** rename target is `--project-path`, not `--path`. `swift package edit --path <checkout>` is public API; a global `--path` alias would collide with `edit`'s subcommand flag at parse time. `--project-path` avoids the collision without an evolution proposal to rename `edit`'s flag.

#### 10. `swift package edit` deferred-feature diagnostic
**File**: `Sources/Commands/PackageCommands/EditCommands.swift`
- ✅ `swift package edit` under a workspace hard-errors via `Basics.Diagnostic.editUnsupportedUnderWorkspace(workspaceRoot:)` pointing at `swift package workspace override`.
- ✅ `swift package unedit` under a workspace hard-errors via `Basics.Diagnostic.uneditUnsupportedUnderWorkspace(workspaceRoot:)` pointing at `swift package workspace override remove`.
- ⚠ **Design change from pitch:** the diagnostic points at the concrete replacement (`swift package workspace override`, shipped in Phase 8C) rather than emitting a generic "will be addressed in a follow-up" placeholder. Users hitting the guard get a concrete next step, not a promise.

#### 11. Workspace-only DSL outside workspace
**Location**: `Workspace.loadRootManifests(...)` at `Sources/Workspace/Workspace.swift`
- ✅ `WorkspaceResolveError` is now propagated through `loadRootManifests` alongside `TraitError` instead of being silently swallowed into an empty manifest set. `.package(workspaceMember:)` / `.package(workspaceInherited:)` in a standalone `Package.swift` (no ancestor `Workspace.swift`) now surfaces the actionable error at the CLI boundary.

#### 12. Fixtures (landed)
**Directory**: `Fixtures/Workspaces/S15_ErrorPaths/`

- `EmptyMembers/`
- `MemberWithoutPackageSwift/`
- `NestedWorkspaceInMember/`
- `NestedWorkspaceInAncestor/`
- `WorkspaceMemberUsedOutsideWorkspace/` — standalone `Package.swift` using `.package(workspaceMember:)`
- `WorkspaceInheritedUsedOutsideWorkspace/` — standalone `Package.swift` using `.package(workspaceInherited:)`

The `WorkspaceAndMultirootBoth/` fixture from the original plan wasn't needed: the check happens at CLI init from any workspace fixture, so `--multiroot-data-file` conflict coverage reuses `S14_DumpPackage`.

#### 13. Functional tests (landed)
- 4 e2e tests using `expectThrowsCommandExecutionError` covering the fixture set above.
- `s15_multirootDataFile_conflictsWithDiscoveredWorkspace` — CLI-init conflict.
- `s15_pathFlag_alone_worksWithoutDeprecationWarning`, `s15_packagePathFlag_alone_worksAndWarns`, `s15_bothPathFlags_lastWinsAndWarns` — flag rename cycle.
- `s15_edit_underWorkspace_hardErrorsPointingAtWorkspaceOverride`, `s15_unedit_underWorkspace_hardErrorsPointingAtWorkspaceOverride` — deferred-feature guards.
- Unit-level coverage: `EditDiagnosticsTests`, `MultirootDataFileConflictDiagnosticTests`, `PackagePathDeprecationWarrantedTests`, `ComputeLocalConfigurationDirectoryTests`.

### Success Criteria

#### Automated Verification:
- [x] Every error scenario in the fixture set produces the documented diagnostic (each `S15_ErrorPaths/*` fixture has a functional test asserting stderr contains the expected specific substring for that scenario)
- [x] `--project-path` and `--package-path` both work; `--package-path` emits stderr containing `"deprecated"` AND `"--project-path"`
- [x] Last-wins semantics if both are set: aliased `@Option` gives ArgumentParser the semantics for free
- [x] `swift package edit` under workspace emits stderr containing `"not supported"` AND `"swift package workspace override"` (and explicitly does NOT contain `"follow-up"`)
- [x] Diagnostic-quality: `WorkspaceResolveError` and `WorkspaceManifestParseError` conform to `CustomStringConvertible` so runtime output reads as prose, not enum reflection
- [x] Full regression green on each sub-slice's stack branch

#### Manual Verification:
(none — all criteria automated)

---

## Phase 16: Trait Isolation Coverage + Cycle Detection

### Overview

Follow-up coverage discovered during Phase 15 stack-top review. Three concerns:

1. **Per-member trait isolation for `.workspaceInherited`.** `resolveInherited` already computed each member's `workspace ∪ member` trait union independently, but the multi-member case had no test coverage. A future refactor of the trait-union arm could silently regress cross-member isolation.
2. **Per-member trait isolation for `.workspaceMember`.** No workspace-level counterpart to merge with, so `resolveWorkspaceMemberPaths` preserves each consumer's authored trait set verbatim. No coverage locking that in.
3. **Cross-package cycle detection through workspace-scoped edges.** For tools-version 6.0+, package-level cycle detection is intentionally disabled (`ModulesGraph+Loading.swift:112`) and the graph relies on the module-level cycle scan (`:892-914`) that follows `.product()` edges. No coverage locking in that `.workspaceMember` / `.workspaceInherited`-resolved packages participate in that scan.

Also discovered during Phase 15 stack-top review: **`swift package describe` crashed on any workspace using `.package(workspaceInherited:)`**. `DescribedPackageDependency.init(from:)` had a `preconditionFailure` on `.workspaceInherited` predicated on a non-existent "rewrite pass" that replaces `.workspaceInherited` with a concrete kind — but the workspaces pipeline preserves `.workspaceInherited` end-to-end and populates the `resolved:` field instead. Fixed by adding a first-class `workspaceInherited(identity:, resolved:)` case to `DescribedPackageDependency`.

### Changes Required (as landed)

#### 1. Trait isolation for `.workspaceInherited`
**Location**: `Tests/WorkspaceTests/WorkspaceResolveTests.swift` + `Tests/FunctionalTests/WorkspaceFeatureTests.swift`

- ✅ 4 unit tests locking per-member `resolveInherited` isolation: two members inheriting the same workspace dep with divergent traits (guards against cross-contamination), two members inheriting different workspace deps (per-dep-scoped traits), mixed nil/explicit fall-through, and the "only one member inherits" case.
- ✅ E2E test `s15_workspaceInheritedTraits_perMemberIsolation_workspaceLoadsAndBuilds` against fixture `Fixtures/Workspaces/S15_InheritedTraits/` (2 members + trait-bearing workspace dep + divergent per-member layered traits).

#### 2. Trait isolation for `.workspaceMember`
**Location**: `Tests/WorkspaceTests/WorkspaceResolveTests.swift` + `Tests/FunctionalTests/WorkspaceFeatureTests.swift`

- ✅ `workspaceMemberDep(identity:traits:productFilter:)` helper added mirroring the existing `inheritedDep(...)`.
- ✅ 4 unit tests locking per-consumer `.workspaceMember` isolation: two members referencing the same target with divergent traits (verbatim preservation, no cross-contamination), two members referencing different targets (per-target-scoped traits), mixed nil/explicit (nil stays nil), and the "only one member references" case.
- ✅ E2E test `s15_workspaceMemberTraits_perMemberIsolation_workspaceLoadsAndBuilds` against fixture `Fixtures/Workspaces/S15_MemberTraits/` (3 members, two consumers referencing the third with divergent traits).

#### 3. Cross-package cycle detection through workspace-scoped edges
**Location**: `Tests/FunctionalTests/WorkspaceFeatureTests.swift`

- ✅ Fixture `Fixtures/Workspaces/S15_WorkspaceMemberCycle/` — two workspace members forming a `.workspaceMember` + `.product()` target cycle.
- ✅ Fixture `Fixtures/Workspaces/S15_WorkspaceInheritedCycle/` — one workspace member inherits an external via `.workspaceInherited`; the external declares a `.package(path:)` back-reference to the member, closing a target cycle.
- ✅ E2E tests `s15_workspaceMemberCycle_hardErrors` and `s15_workspaceInheritedCycle_hardErrors` — both use `swift package describe` (which triggers full graph load without incurring compile time) and assert stderr contains `"cyclic dependency declaration"` plus both cycle-path target names.

Test-only change — no production code touched. Cycle detection already worked; there was no coverage locking it in for the workspace DSL cases.

#### 4. `swift package describe` handles `.workspaceInherited`
**File**: `Sources/Commands/Utilities/DescribedPackage.swift`

- ✅ Added first-class `case workspaceInherited(identity: PackageIdentity, resolved: ResolvedInherited)` to `DescribedPackageDependency`, mirroring the existing `workspaceMember` case.
- ✅ Nested `enum ResolvedInherited: Encodable` with `.fileSystem`, `.sourceControl`, `.registry` sub-cases mirrors `PackageDependency.WorkspaceInherited.ResolvedInherited` in describe-appropriate shape (source-control location as a string, no `nameForTargetDependencyResolutionOnly` / `registryIdentity` metadata that isn't part of describe output).
- ✅ `init(from:)` unpacks `settings.resolved` into the describe case. Preserved a `preconditionFailure` for the "nil resolved" invariant violation, retooled with a message pointing at `resolveInherited` (the field's populator) rather than the non-existent rewrite pass the previous message referenced.
- ✅ Added `.resolved` coding key + `.workspaceInherited` to `Kind` + encoding branch.
- ✅ Unit tests `DescribedPackageDependencyTests` (new file, 4 tests) — `.workspaceInherited` round-trip through `init(from:)` for all three resolved variants (file-system, source-control remote, source-control local, registry).

### Success Criteria

#### Automated Verification:
- [x] Multi-member `.workspaceInherited` unit tests lock cross-member trait isolation (workspace ∪ member per member, no cross-contamination)
- [x] Multi-member `.workspaceMember` unit tests lock per-consumer verbatim preservation
- [x] E2E tests exercise the full manifest-load pipeline for both DSL forms with divergent per-member traits
- [x] Cycle detection e2e tests exercise both DSL edge kinds
- [x] `DescribedPackageDependencyTests` (new suite) unit tests cover all three resolved variants for `.workspaceInherited`
- [x] `swift package describe` on any workspace using `.package(workspaceInherited:)` no longer crashes
- [x] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Cross-Cutting Concerns

These items don't belong to any single slice but must be addressed during implementation.

### Manifest cache invalidation

SwiftPM caches evaluated manifests (`Sources/PackageLoading/ManifestLoader.swift`). The cache key includes the manifest path, tools-version, and content hash. Since `Workspace.swift` is loaded through the same `evaluateManifest()` pipeline as `Package.swift`, it will be cached transparently — no new cache infrastructure is needed. The distinct filename ensures no cache collision with same-directory `Package.swift`.

**Slice landing this**: Slice 1 (verify during implementation; add a unit test that a second load of the same `Workspace.swift` produces a byte-identical `WorkspaceManifest` and does not re-invoke the evaluator subprocess).

### Cross-platform path handling

- **Windows path separators**: `PackageIdentity.computeDefaultName(fromPath:)` at `Sources/PackageModel/PackageIdentity.swift:314` already handles both `/` and `\` — no changes needed.
- **Case sensitivity**: `PackageIdentity` is lowercased. `Workspace.swift` filename is case-sensitive on Linux, case-insensitive on macOS/Windows — matches existing `Package.swift` behavior.
- **Symlink resolution**: member paths resolved via canonical (`realpath`) resolution to compute identity. Duplicate-identity detection uses canonical paths, so `packages/lib-a` and `packages/lib-a-symlink → lib-a` are correctly detected as duplicates.
- **UNC / drive-relative paths on Windows**: absolute-path rejection already covers these — any path starting with `C:` or `\\` fails the "must be relative" check.

**Slices landing these**: Slice 1 (canonical path resolution + duplicate detection); Slice 15 (Windows-specific error path fixtures).

### Trait system interaction

The `Set<Trait>` type on `PackageDependency.WorkspaceMember` / `WorkspaceInherited` mirrors the existing `traits:` parameter on `.package(url:)` / `.package(path:)` / `.package(id:)`. Trait union at rewrite time uses standard `Set.union(_:)`. No new trait resolution semantics — the resulting concrete `.fileSystem` / `.sourceControl` / `.registry` dep is trait-resolved by the existing pipeline.

**Slice landing this**: Slice 3 (trait union in rewrite pass).

### Interaction with `SwiftCommandState.getWorkspaceRoot()` and `--path` / `--package-path`

Order of operations when the CLI starts:

1. Argument parsing (`--path`, `--package-path`, `--multiroot-data-file`) resolved by `SwiftCommandState.postprocessArgParserResult()`.
2. Change working directory to `--path` value (existing behavior).
3. `getWorkspaceRoot()` walks up from CWD (now at `--path`).
4. If `Workspace.swift` found in walk-up → workspace loading path.
5. Else if `--multiroot-data-file` set → existing Xcode workspace loading path.
6. Else standard single-package walk-up for `Package.swift`.

Conflict detection: if `--multiroot-data-file` AND a walk-up `Workspace.swift` are both discoverable → hard error (Slice 15).

**Slice landing this**: Slice 1 (walk-up); Slice 15 (conflict detection).

### `--path` / `--package` build-lock anchored to the wrong `.build/` (open follow-up)

`swift-build --path <target-dir> --package <name>` acquires the PID
build lock on the *invoker's* CWD `.build/` rather than the
target's. Reproducer, from a repo with its own `.build/`:

```
$ $(swift build --show-bin-path)/swift-build --path ../../swiftlang_test --package swift-package-manager
Another instance of SwiftPM (PID: 89580) is already running using
'/Users/bkhouri/Documents/git/public/swiftlang/swift-package-manager-3/.build',
waiting until that process has finished execution...
```

The invocation should route the lock to `<target>/.build/` (or the
enclosing workspace's `.build/`). Not blocking any current slice —
the workspace state-routing infrastructure landed in Slices 8/12 is
the right lever to fix it. Follow-up: track the lock-file path
through the same `computeResolvedVersionsFile` / `getLocalConfigurationDirectory`
decision helpers so `--path` and `--package` reach the same anchor
as everything else.

### libSwiftPM public API surface added by this plan

Summary of net new public API (all in the `Workspace` module unless noted):

- `PackageWorkspace` (renamed from `Workspace`, Slice 0)
- `public typealias Workspace = PackageWorkspace` (deprecated, Slice 0)
- `WorkspaceManifest`, `WorkspaceManifest.Member`, `WorkspaceManifest.StateDirectoryKind` (in `PackageModel`, Slice 1)
- `PackageWorkspace.discoverWorkspaceRoot(from:fileSystem:) -> AbsolutePath?` (Slice 1)
- `PackageWorkspace.loadWorkspaceManifest(at:observabilityScope:) async throws -> WorkspaceManifest` (Slice 1)
- New `PackageGraphRootInput.workspaceManifest` optional field (in `PackageGraph`, Slice 2)
- New cases on `PackageDependency.Kind`: `.workspaceMember`, `.workspaceInherited` (in `PackageModel`, Slice 2-3)
- New structs `PackageDependency.WorkspaceMember`, `PackageDependency.WorkspaceInherited` (Slice 2-3)
- New case on `BuildSubset`: `.workspaceMember(PackageIdentity)` (in `SPMBuildCore`, Slice 4)
- New DSL types in `PackageDescription`: `Workspace`, `Workspace.Member`, `Workspace.StateDirectoryKind`, and the two `.package(workspaceMember:)` / `.package(workspaceInherited:)` factory methods (Slices 1-3)

All additions gated on `@available(_PackageDescription, introduced: 999.0)` where applicable. All PackageModel/Workspace additions live behind SwiftPM's "unstable API" disclaimer.

---

## Testing Strategy

### Per-slice tests (Fixture-driven functional)

Each slice adds one or more `@Test` methods to `Tests/FunctionalTests/WorkspaceFeatureTests.swift`, running against `Fixtures/Workspaces/S<NN>_*/`. Uses Swift Testing (per Sam K's memory: preferred over XCTest for new files).

Test conventions:
- `try #require` for preconditions (per Sam K's memory).
- Multi-line function calls with trailing commas (per Sam K's memory).
- `@Test(arguments: SupportedBuildSystemOnAllPlatforms)` to run across both build systems.

### Unit tests

- `Tests/WorkspaceTests/WorkspaceManifestTests.swift` (new) — DSL evaluation, JSON parsing, validation rules. Uses `MockWorkspace` + `InMemoryFileSystem`.
- `Tests/WorkspaceTests/PackageWorkspaceDeprecationTests.swift` (Slice 0) — typealias behavior.
- `Tests/CommandsTests/InitWorkspaceTests.swift` (Slice 9) — scaffolding logic in isolation.

### Full regression

Every slice commit runs the full existing suite:
```
swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure
```

### Definition of done per slice

A slice is complete when:
1. Its fixture exists and is minimal.
2. Its functional test passes.
3. Full regression green.
4. Commit message references the slice number and a one-line summary.

## Performance Considerations

- **Rewrite pass** runs once per workspace load. Bounded by number of members × average deps per member. For realistic workspaces (10s of members × 10s of deps), overhead is negligible relative to manifest evaluation itself.
- **Discovery walk-up** adds one `fileSystem.exists()` check per ancestor directory. Terminates at filesystem root or at any Workspace.swift/Package.swift. Same order-of-magnitude as existing walk-up.
- **State-file scan** at end of command reads directory entries under each member path (single `.exists()` per candidate). O(members × 4).
- **`.build/` unification** may actually improve performance (shared cache across members) compared to per-member `.build/` today under `--multiroot-data-file`.

No performance-oriented changes are required for MVP.

## Migration Notes

- **Existing single-package repos**: zero impact. Discovery walk-up looking for `Workspace.swift` returns nil for any repo without one.
- **Existing `--multiroot-data-file` users (primarily Xcode)**: continue to work; deprecation warning strengthened to reference Workspace.swift. Hard error only when both are specified.
- **Existing `--package-path` users**: continue to work; deprecation warning; users can migrate to `--path` at their leisure.
- **libSwiftPM consumers (SourceKit-LSP)**: rebuild against renamed `PackageWorkspace` (typealias covers one release). New `WorkspaceManifest` API available for opt-in workspace-aware UI.
- **Downstream code exhaustively switching on `PackageDependency.Kind`**: gets `@unknown default` warnings on Slice 2 + Slice 3 commits. Unfrozen enum semantics → warnings, not errors.

## References

- SE proposal: `/Users/bkhouri/Documents/git/public/swiftlang/swift-evolution/proposals/NNNN-swiftpm-workspaces.md`
- Existing `Workspace` class: `Sources/Workspace/Workspace.swift:77`
- `WorkspaceLoader` protocol: `Sources/CoreCommands/SwiftCommandState.swift:1425`
- `PackageGraphRootInput`: `Sources/PackageGraph/PackageGraphRoot.swift:19`
- PubGrub synthesized-root: `Sources/PackageGraph/Resolution/PubGrub/PubGrubDependencyResolver.swift:180`
- BuildPlan multiroot FIXME: `Sources/Build/BuildPlan/BuildPlan.swift:687`
- `999.0` availability convention: `Sources/PackageModel/ToolsVersion.swift:39`
- Existing fixture-driven tests: `Tests/FunctionalTests/DependencyResolutionTests.swift`
- Test infrastructure: `Sources/_InternalTestSupport/MockWorkspace.swift`, `Fixtures/`
- Branch: `bkhouri/t/main/poc_workspaces`
