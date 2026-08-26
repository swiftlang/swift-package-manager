// swift-tools-version: 999.0
import PackageDescription

let workspace = Workspace(
    members: [
        "packages/member-a",
        "packages/member-b",
        "packages/member-c",
        "packages/lib-only",
    ],
)
