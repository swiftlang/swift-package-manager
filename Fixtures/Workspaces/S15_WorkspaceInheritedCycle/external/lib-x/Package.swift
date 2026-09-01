// swift-tools-version: 999.0
import PackageDescription

// External workspace-level dep for the S15_WorkspaceInheritedCycle
// fixture. Declares a target LibX that depends on the LibA product
// from the workspace member lib-a via a `.package(path:)` back-
// reference. Combined with lib-a's `.workspaceInherited("lib-x")`
// and target LibA -> product LibX, this forms a target cycle
// LibA <-> LibX that graph-load must reject.
let package = Package(
    name: "lib-x",
    products: [
        .library(name: "LibX", targets: ["LibX"]),
    ],
    dependencies: [
        .package(path: "../../packages/lib-a"),
    ],
    targets: [
        .target(
            name: "LibX",
            dependencies: [
                .product(name: "LibA", package: "lib-a"),
            ],
        ),
    ],
)
