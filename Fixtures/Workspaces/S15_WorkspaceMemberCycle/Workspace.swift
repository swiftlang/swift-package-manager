// swift-tools-version: 999.0
import PackageDescription

// S15_WorkspaceMemberCycle fixture: a workspace declares two members
// (`lib-a`, `lib-b`), each of which depends on the OTHER via
// `.package(workspaceMember:)` at the package level AND `.product()`
// at the target level. The mutual product edges (LibA imports LibB
// / LibB imports LibA) form a target-level cycle that must be
// rejected at graph load with a `cyclic dependency declaration`
// diagnostic. Locks in that `.workspaceMember` edges participate in
// cycle detection just like ordinary `.package(path:)` edges.
let workspace = Workspace(
    members: [
        "packages/lib-a",
        "packages/lib-b",
    ],
)
