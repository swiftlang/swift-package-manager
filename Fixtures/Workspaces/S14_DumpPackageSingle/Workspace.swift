// swift-tools-version: 999.0
import PackageDescription

// S14_DumpPackageSingle fixture: a workspace with exactly one
// member. Locks in that `swift package dump-package` at a
// single-member workspace root behaves like the pre-workspaces
// non-workspace case — it auto-selects the sole member without
// requiring `--package <identity>`.
let workspace = Workspace(
    members: [
        "packages/app",
    ],
)
