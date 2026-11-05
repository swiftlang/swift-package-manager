// swift-tools-version: 5.9
import PackageDescription

// Example 03 declares the same URL twice and crashes in the graph, because both declarations have the same
// name ("shared") and the product lookup key "<name>_<product>" collides. Here each declaration gets its OWN
// explicit name, using the deprecated `.package(name:url:_:)` spelling (deprecated in 5.6, not obsoleted, so it
// still compiles with a warning).
//
// Hypothesis (from reading the code, not from a run): the keys become `sharedv1_Shared` / `sharedv2_Shared`, each
// declaration's own range picks its own bucket, and because the target then depends on two same-named modules from
// different products the build uses the renamed names directly. If so the root can write BOTH `import Shared_v1`
// and `import Shared_v2`, symmetrically, with no new manifest API.
let package = Package(
    name: "named-declarations",
    dependencies: [
        .package(name: "SharedV1", url: "file:///tmp/multi-major-fixtures/Shared", "1.0.0"..<"2.0.0"),
        .package(name: "SharedV2", url: "file:///tmp/multi-major-fixtures/Shared", "2.0.0"..<"3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "named",
            dependencies: [
                .product(name: "Shared", package: "SharedV1"),
                .product(name: "Shared", package: "SharedV2"),
            ]
        ),
    ]
)
