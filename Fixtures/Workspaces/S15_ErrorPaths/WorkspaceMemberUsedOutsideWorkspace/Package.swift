// swift-tools-version: 999.0
import PackageDescription

// S15_ErrorPaths/WorkspaceMemberUsedOutsideWorkspace fixture:
// a standalone Package.swift (no Workspace.swift anywhere in its
// ancestry) that references a workspace-only DSL entry point,
// `.package(workspaceMember:)`. Loading this manifest must fail
// with the actionable `workspaceMemberUsedOutsideWorkspace`
// error — the DSL is only meaningful inside a SwiftPM workspace.
let package = Package(
    name: "orphan",
    dependencies: [
        .package(workspaceMember: "lib-a"),
    ],
    targets: [
        .target(
            name: "orphan",
            dependencies: [
                .product(name: "LibA", package: "lib-a"),
            ],
        ),
    ],
)
