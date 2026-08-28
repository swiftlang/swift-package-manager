// swift-tools-version: 999.0
import PackageDescription

// Workspace layout used by Phase 10's `show-dependencies` fixtures:
//   - Two members (`app`, `lib-a`) so the dumpers see a multi-root
//     graph. `app` depends on `lib-a` via `.package(workspaceMember:)`
//     — that edge is what carries the `[workspace member]` tag in the
//     text format.
//   - One workspace-level `some-lib` dep both members inherit via
//     `.package(workspaceInherited:)` — collapses to a single entry in
//     the deduplicated flatlist output.
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
    ],
    dependencies: [
        .package(path: "external/some-lib"),
    ],
)
