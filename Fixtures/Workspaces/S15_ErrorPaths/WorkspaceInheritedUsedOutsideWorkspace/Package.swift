// swift-tools-version: 999.0
import PackageDescription

// S15_ErrorPaths/WorkspaceInheritedUsedOutsideWorkspace fixture:
// a standalone Package.swift (no Workspace.swift anywhere in its
// ancestry) that references `.package(workspaceInherited:)`. The
// DSL is only meaningful inside a SwiftPM workspace; loading this
// manifest must fail with the actionable
// `workspaceInheritedUsedOutsideWorkspace` error.
let package = Package(
    name: "orphan",
    dependencies: [
        .package(workspaceInherited: "some-lib"),
    ],
    targets: [
        .target(
            name: "orphan",
            dependencies: [
                .product(name: "SomeLib", package: "some-lib"),
            ],
        ),
    ],
)
