// swift-tools-version: 999.0
import PackageDescription

let workspace = Workspace(
    members: [
        "packages/app",
        "packages/lib-a",
        "packages/lib-b",
    ],
    dependencies: [
        .package(path: "external/some-lib"),
    ],
)
