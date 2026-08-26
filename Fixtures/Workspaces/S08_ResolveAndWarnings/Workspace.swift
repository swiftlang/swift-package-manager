// swift-tools-version: 999.0
import PackageDescription

let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
        .member(
            path: "packages/lib-b",
            ignoredStateDirectories: [.build],
        ),
    ],
    dependencies: [
        // Source-control dependency (not path-based) so that
        // `swift package resolve` records an entry in
        // `Package.resolved`. The `external/some-lib` directory is
        // shipped without a `.git` folder; each test that exercises
        // resolve initializes it as a git repo at runtime and tags
        // it 1.0.0. See S08 test helpers in
        // Tests/FunctionalTests/WorkspaceFeatureTests.swift.
        .package(url: "external/some-lib", from: "1.0.0"),
    ],
)
