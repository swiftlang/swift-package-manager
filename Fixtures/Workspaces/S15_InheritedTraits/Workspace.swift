// swift-tools-version: 999.0
import PackageDescription

// S15_InheritedTraits fixture: a workspace declares two members
// (`app`, `lib-a`) and a single workspace-level dependency
// `traited-lib` with traits `["core"]`. Each member inherits
// `traited-lib` via `.package(workspaceInherited:)` but layers a
// DIFFERENT additional trait on top — `app` adds `"extras"`,
// `lib-a` adds `"perf"`. This exercises the per-member
// `resolveInherited` merge policy end-to-end: `app`'s resolved
// trait set is `{core, extras}` while `lib-a`'s is `{core, perf}`,
// with no cross-contamination.
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
    ],
    dependencies: [
        .package(
            path: "external/traited-lib",
            traits: [
                "core",
            ],
        ),
    ],
)
