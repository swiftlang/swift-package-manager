// swift-tools-version: 999.0
import PackageDescription

// S15_ErrorPaths/NestedWorkspaceInAncestor OUTER workspace: a
// well-formed workspace with one member `inner`. But `inner`
// itself is another workspace root (see inner/Workspace.swift) —
// nested workspaces are not supported, so the inner one's load
// must fail.
//
// The e2e test invokes `swift package` inside `inner/`, walking
// up finds `inner/Workspace.swift` first, and load-time
// validation then walks up further and detects THIS outer
// Workspace.swift as an ancestor.
let workspace = Workspace(
    members: [
        "inner",
    ],
)
