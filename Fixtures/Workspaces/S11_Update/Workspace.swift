// swift-tools-version: 999.0
import PackageDescription

// S11_Update fixture: two workspace members each inheriting a
// distinct external source-control dependency. Slice 11 uses this
// shape to verify that `swift package update --package <identity>`
// restricts fresh pins to the named member's transitive dep subtree
// while preserving pins for the other member's subtree.
//
// The external/*/ directories ship without `.git`; each test that
// exercises `update` initializes them as git repos + tags `1.0.0`
// via the `initializeExternalRepo` helper — same pattern as S08.
let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
    ],
    dependencies: [
        .package(url: "external/some-lib", from: "1.0.0"),
        .package(url: "external/other-lib", from: "1.0.0"),
    ],
)
