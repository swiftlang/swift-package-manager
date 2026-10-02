// swift-tools-version: 999.0
import PackageDescription

// Workspace layout used by Phase 10's `show-dependencies` fixtures:
//   - Two members (`app`, `lib-a`) so the dumpers see a multi-root
//     graph. `app` depends on `lib-a` via `.package(workspaceMember:)`
//     — that edge is what carries the `[workspace member]` tag in the
//     text format.
//   - Both members directly declare `.package(path: "../../external/some-lib")`
//     — the deduplicated flatlist output collapses them to a single entry.
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
    ],
)
