// swift-tools-version: 999.0
import PackageDescription

// S13_Describe fixture: two workspace members with no external
// dependencies. `swift package describe` is a static-analysis
// command — it iterates the manifests and prints their target /
// product / dependency structure without needing anything on the
// wire — so this fixture stays minimal.
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
    ],
)
