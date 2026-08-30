// swift-tools-version: 999.0
import PackageDescription

// S15_ErrorPaths/NestedWorkspaceInMember fixture: a well-formed
// outer workspace whose member `packages/lib-a` accidentally
// contains its own Workspace.swift. Load-time validation must
// reject this — nested workspaces have undefined shared-state
// semantics.
let workspace = Workspace(
    members: [
        "packages/lib-a",
    ],
)
