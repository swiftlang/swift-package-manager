# SwiftPM Workspaces — Implementation Plan

## Overview

Implement first-class workspaces in Swift Package Manager: a new `Workspace.swift` manifest declares multiple member packages with unified dependency resolution, shared build state, and consistent CLI ergonomics. Design is locked in `/Users/bkhouri/Documents/git/public/swiftlang/swift-evolution/proposals/NNNN-swiftpm-workspaces.md`.

**Delivery model:** one commit per slice on branch `bkhouri/t/main/poc_workspaces`. Strict linear order. No PRs created by this plan — Sam K creates the PR stack himself via `gh-stack` after the branch is complete.

**Gating:** all new DSL surface gated on `@available(_PackageDescription, introduced: 999.0)` using SwiftPM's existing `vNext` convention (`Sources/PackageModel/ToolsVersion.swift:39`). Graduation to a real tools-version is out of scope for this plan.

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

- `swift package edit` / `swift package unedit` under workspace (Slice 15 emits a deferred-feature diagnostic; actual implementation is post-MVP).
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
- [ ] Add `PackageWorkspaceRenameTests.noOldClassNameRemains` that shells out to `grep -rn '\bclass Workspace\b' Sources/Workspace/` and asserts zero hits — mechanical regression guard against reintroducing the old declaration
- [ ] Add `PackageWorkspaceRenameTests.typealiasEmitsDeprecationWarning` that compiles a small Swift snippet using the `Workspace` typealias in a subprocess with `-warnings-as-errors` OR captures compiler diagnostics stream and asserts the deprecation diagnostic is present

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
- [ ] `swift build --disable-sandbox` succeeds
- [ ] `swift test --disable-sandbox --filter WorkspaceFeatureTests --xunit-output xunit.xml --experimental-xunit-message-failure` — Slice 1 test green
- [ ] Full regression: `swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure` — all existing tests still pass
- [ ] `Fixtures/Workspaces/S01_MinimalTwoMembers/` exists and builds from its root
- [ ] Test assertion: after `executeSwiftBuild` completes, both `<fixturePath>/.build/debug/lib-a.o` (or equivalent product) and `<fixturePath>/.build/debug/lib-b.o` exist
- [ ] Test assertion: no `Package.resolved` file exists at `<fixturePath>/packages/lib-a/` or `<fixturePath>/packages/lib-b/` after build
- [ ] Test assertion: `.build/` exists only at workspace root, not per-member

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
- [ ] Slice 2 fixture builds; app links against lib-a
- [ ] `swift test --disable-sandbox --xunit-output xunit.xml --experimental-xunit-message-failure` — full suite green
- [ ] Loading a member `Package.swift` with `.package(workspaceMember:)` outside a workspace errors with the documented diagnostic
- [ ] Test assertion: running the built `app` binary from the fixture's `.build/` produces stdout containing "Hello from lib-a"
- [ ] Test assertion: outside-workspace stderr contains `"requires a Workspace.swift in an ancestor directory"` (exact substring match)

#### Manual Verification:
(none — all criteria automated)

---

## Phase 3: `.package(workspaceInherited:)` DSL

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
- [ ] Slice 3 fixture builds; both members import from the same resolved version of the external
- [ ] Test assertion: the resolved graph reports exactly one `SomeLib` package (no duplicate resolution)
- [ ] Unknown-inherited-identity fixture fails with stderr containing `"no workspace-level dependency"`
- [ ] Trait-variant fixture: workspace declares `traits: ["A"]`; member inherits with `traits: ["B"]`; test asserts the resolved dep has `traits: ["A", "B"]` via graph inspection
- [ ] Unused-workspace-dep fixture: workspace declares a dep no member inherits; test asserts stderr contains `"declared in Workspace.swift but not inherited by any member"` at end of `swift package resolve`
- [ ] Full regression green

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
- [ ] From inside `packages/app`, `swift build` builds only app + its transitive deps
- [ ] The workspace-inherited `SomeLib` resolves correctly (workspace graph is used)
- [ ] `lib-a` is not built when unrelated
- [ ] Full regression green
- [ ] Test assertion: `.build/` exists at workspace root, not inside `packages/app/`. Check `<fixturePath>/.build/` exists and `<fixturePath>/packages/app/.build/` does not
- [ ] Test assertion: `executeSwiftBuild(memberPath, extraArgs: ["--show-bin-path"])` from inside the member returns a path under `<fixturePath>/.build/`

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
- [ ] `--package <valid>` from workspace root builds that member only
- [ ] `--package <valid>` from inside another member builds the selected member
- [ ] `--package <invalid>` errors with stderr containing `"no workspace member with identity"` AND each known member identity listed (test iterates known identities and asserts each is in stderr)
- [ ] `--package` outside a workspace errors with stderr containing `"requires a Workspace.swift"`
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 6: `swift test` in Workspace

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
- [ ] `swift test --xunit-output xunit.xml --experimental-xunit-message-failure` at workspace root runs both members' tests
- [ ] The xunit.xml file has `package="<identity>"` on each `<testsuite>` — parse the XML and assert
- [ ] `--filter` narrows across all in-scope tests: apply a filter matching tests in only one member, assert only those ran (via xunit parse)
- [ ] Test assertion: parse xunit; `sum(testsuite.tests) == expected-total-across-both-members` when running at root, `== expected-just-lib-a` with `--package lib-a`
- [ ] Test assertion: stdout console output contains member identifiers alongside test suite names (grep for expected member-scoped test-suite lines)
- [ ] Full regression green

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
- [ ] Ambiguous exec at root errors with stderr containing `"ambiguous executable"` AND both member identities AND product names
- [ ] From inside a member, cross-member exec is not silently found: `swift run <other-member-exec>` from inside member-A errors with `"not found"`
- [ ] `--package X <exec>` resolves cross-member from anywhere: exit code 0, expected stdout from `hello` executable
- [ ] Full regression green

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
- [ ] `swift package resolve` at workspace root writes `Package.resolved` at workspace root
- [ ] Test assertion: no `Package.resolved` written per-member — `<memberPath>/Package.resolved` does not exist after workspace resolve (unless one was pre-existing)
- [ ] Trailing warning aggregates member state findings — stderr contains `"workspace members have ignored state"` after resolve, with each detected member listed
- [ ] `ignoredStateDirectories` suppresses per-kind warnings — variant fixture where a member declares `[.build]` in its Member declaration; assert `.build/` is NOT in the warning output for that member
- [ ] BuildPlan FIXME resolved: test that after `swift build`, the build-input tracking references the workspace-root Package.resolved (inspect llbuild manifest or use an equivalent SwiftPM internal API)
- [ ] originHash test: resolve → capture originHash A; modify workspace-level dependency → resolve → capture originHash B; assert A != B
- [ ] Warning-at-end test: capture stdout+stderr with timestamps or order markers; assert the trailing warning comes AFTER build/resolve status lines (grep for warning line index > last resolve-progress line index)
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 9: `swift package init workspace`

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
- [ ] `swift package init workspace` creates `Workspace.swift`
- [ ] `swift package init workspace --members lib-a app:executable` creates buildable workspace
- [ ] `swift package init` (bare) still routes to `init package` (backward compat): assert `Package.swift` (not `Workspace.swift`) is created
- [ ] `swift package init --type executable` still works via defaultSubcommand: assert generated `Package.swift` contains `.executableTarget`
- [ ] `swift package init --help` output contains both `package` and `workspace` in the subcommand listing (stdout grep)
- [ ] Info-line test: run `init workspace --members existing-lib-a` where `existing-lib-a/Package.swift` already exists; assert stdout contains `"already has a Package.swift"` AND the existing file is byte-identical before/after
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 10: `swift package show-dependencies` Workspace Awareness

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
- [ ] `show-dependencies --format text` from workspace root prints all members with headers; workspace-member deps have `[workspace member]` tag
- [ ] `show-dependencies --format dot` output has one `subgraph cluster_<identity>` block per in-scope member (grep-asserted)
- [ ] `show-dependencies --format flatlist` output is deduplicated across members (distinct-count matches expected)
- [ ] `show-dependencies --package X` restricts to X's tree from anywhere
- [ ] `show-dependencies` from inside member M shows M's tree only
- [ ] Non-workspace-member path deps do NOT carry the `[workspace member]` tag (test explicit)
- [ ] Existing single-package `show-dependencies` behavior unchanged (regression fixture from prior tests)
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 11: `swift package update` Workspace Awareness

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
- [ ] `update` from workspace root updates all members' deps in workspace `Package.resolved`
- [ ] `update --package X` restricts writes to X's subtree — byte-compare workspace `Package.resolved` before/after; only X-subtree pins may differ
- [ ] From inside member M, `update` restricts to M's subtree
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 12: `swift package clean` Workspace Awareness

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
- [ ] `clean` removes `<workspace-root>/.build/`; file-existence check confirms
- [ ] `clean` from inside a member emits stdout containing `"cleaning workspace build directory:"`
- [ ] `clean --package X` under workspace emits stdout containing `"--package has no effect for 'clean'"` AND exits 0 (info, not error)
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 13: `swift package describe` Workspace Awareness

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
- [ ] `describe` from workspace root emits all members' descriptions each preceded by `--- <identity> ---` header
- [ ] `describe` from inside member M shows M's description only (no header, since unambiguous)
- [ ] `describe --package X` restricts to X's description
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---

## Phase 14: `swift package dump-package` Workspace Awareness

### Overview

Extend `swift package dump-package` for workspace disambiguation. `dump-package` returns exactly one manifest as JSON — with N members, we need to know which.

**Behavior:**
- **From workspace root without `--package`**: hard error (ambiguous).
- **From inside member M**: dumps M's manifest (CWD is unambiguous — Case A applies).
- **With `--package X`**: dumps X's manifest, overriding CWD.

### Changes Required

#### 1. Enforce disambiguation
**File**: `Sources/Commands/PackageCommands/DumpPackage.swift`

Detect workspace context + CWD position. From workspace root without `--package`: hard error `"dump-package requires --package <identity> in a workspace; known members: [...]"`. From inside a member: auto-select that member. With `--package X`: dump X.

Note: `Workspace.swift` itself is not dumpable via this command. A future `swift package dump-workspace` may cover that (post-MVP; documented in "What We're NOT Doing").

#### 2. Fixture
**Directory**: `Fixtures/Workspaces/S14_DumpPackage/`

2-member workspace with distinct declared targets/products in each member.

#### 3. Functional tests

```swift
@Test func s14_dumpPackageAtWorkspaceRootWithoutSelectorErrors(...) async throws
@Test func s14_dumpPackageWithSelectorOutputsMemberManifest(...) async throws
@Test func s14_dumpPackageFromInsideMemberAutoSelects(...) async throws
```

### Success Criteria

#### Automated Verification:
- [ ] From workspace root without `--package`: stderr contains `"requires --package"` AND lists known member identities; exit code non-zero
- [ ] `dump-package --package X` under workspace outputs valid JSON containing the `"name"` field matching X's manifest
- [ ] From inside member M without `--package`: dumps M's manifest (JSON containing M's name)
- [ ] Full regression green

#### Manual Verification:
(none — all criteria automated)

---



## Phase 15: Error Paths + Edge Cases

### Overview

Cover all documented error paths and edge cases. `--path`/`--package-path` deprecation. `--multiroot-data-file` conflict. Nested workspaces. Empty members. Absolute paths. Workspace-only DSL outside workspace. `swift package edit` deferred-feature error.

### Changes Required

#### 1. Empty `members: []`
**Location**: workspace manifest validation in `PackageWorkspace.loadWorkspaceManifest()`
- Hard error: `"Workspace.swift declares no members"`.

#### 2. Absolute member paths
**Location**: same validation site
- Hard error: `"member path '<path>' must be relative to Workspace.swift"`.

#### 3. Out-of-tree member paths
**Location**: same validation site
- Warning: `"member '<identity>' at '<path>' is outside the workspace directory tree — this may reduce portability"`.

#### 4. Duplicate member identities
- Hard error at load with the colliding paths.

#### 5. Member path doesn't exist / has no Package.swift
- Hard error with which member and which path.

#### 6. Nested workspace at load-time
**Location**: after member paths are resolved, scan each member's subtree for `Workspace.swift` (bounded depth or fast rejection — depth 1 sufficient in MVP).
- Hard error with member path.

#### 7. Nested workspace at discovery-time
**Location**: `PackageWorkspace.discoverWorkspaceRoot(from:fileSystem:)`
- After finding the first Workspace.swift, continue walking up. If a second Workspace.swift is found in an ancestor, hard error listing both paths.

#### 8. `--multiroot-data-file` conflict
**Location**: `SwiftCommandState.postprocessArgParserResult` (`SwiftCommandState.swift:514`)
- If both `--multiroot-data-file` is set AND a `Workspace.swift` is discoverable in CWD's ancestors → hard error.

#### 9. `--path` / `--package-path` renaming
**File**: `Sources/CoreCommands/Options.swift`
- Add `@Option(name: .customLong("path"), ...) public var path: AbsolutePath?`.
- Keep `--package-path` with `@available(*, deprecated, message: "use --path")` (or equivalent for ArgumentParser).
- In `SwiftCommandState`, `path` takes precedence over `packageDirectory`; if `packageDirectory` is set, emit deprecation warning.

#### 10. `swift package edit` deferred-feature diagnostic
**File**: `Sources/Commands/PackageCommands/Edit.swift`
- If a workspace is discoverable → hard error: `"swift package edit is not yet supported under a Workspace; will be addressed in a follow-up"`.
- Same for `unedit`.

#### 11. Workspace-only DSL outside workspace
**Location**: rewrite pass (Slice 2/3 groundwork)
- Already implemented in Slice 2 via `WorkspaceError.workspaceOnlyAPIOutsideWorkspace`. Slice 15 adds explicit test coverage.

#### 12. Fixtures
**Directory**: `Fixtures/Workspaces/S15_ErrorPaths/`

One subdirectory per error case:
- `EmptyMembers/`
- `AbsoluteMemberPath/`
- `OutOfTreeMember/`
- `DuplicateIdentities/`
- `MissingMemberPath/`
- `MemberWithoutPackageSwift/`
- `NestedWorkspaceInMember/`
- `NestedWorkspaceInAncestor/`
- `WorkspaceAndMultirootBoth/` (with an Xcode workspace file alongside a Workspace.swift)
- `WorkspaceOnlyAPIOutsideWorkspace/` (member Package.swift with `.workspaceMember(...)` but no ancestor Workspace.swift)

#### 13. Functional tests
For each fixture, a `@Test` case that expects the specific diagnostic. Use `try #require` (per Sam K's memory) for preconditions:

```swift
@Test
func s10_emptyMembersHardError(...) async throws {
    try await fixture(name: "Workspaces/S15_ErrorPaths/EmptyMembers") { fixturePath in
        let result = try await executeSwiftBuild(
            fixturePath,
            expectFailure: true,
        )
        try #require(result.exitCode != 0)
        #expect(result.stderr.contains("Workspace.swift declares no members"))
    }
}
```

### Success Criteria

#### Automated Verification:
- [ ] Every error scenario in the fixture set produces the documented diagnostic (each `S15_ErrorPaths/*` fixture has a functional test asserting stderr contains the expected specific substring for that scenario)
- [ ] `--path` and `--package-path` both work; `--package-path` emits stderr containing `"deprecated"` AND `"--path"`
- [ ] `--path` takes precedence if both are set: run `swift build --path /a --package-path /b`, assert only `/a` is loaded (e.g., resolve fails predictably against `/a`, not `/b`)
- [ ] `swift package edit` under workspace emits stderr containing `"not yet supported under a Workspace"`
- [ ] Diagnostic-quality test: each error-path test not only asserts the specific error keyword, but also asserts the diagnostic includes an actionable hint (e.g. suggested fix, file path, member identity) — assert stderr matches a compiled regex `error: .+\n(.+\n)+.+(remove|use|add|specify|--\w+|packages/\w+)` per scenario
- [ ] Full regression green

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
