// swift-tools-version: 5.9
import PackageDescription

// Baseline: the same shape as Examples/multi-majors-prototype. Two libraries pin different majors of
// Shared and the root has no direct dependency on it. Examples 01, 02 and 04 failed during resolution
// (see README "Findings so far"), so this is the one most likely to get through to aliasing and show
// what the libraries actually see.
let package = Package(
    name: "two-majors-libs-only",
    dependencies: [
        .package(path: "../libs/LibOne"),
        .package(path: "../libs/LibTwo"),
    ],
    targets: [
        .executableTarget(
            name: "two",
            dependencies: [
                .product(name: "LibOne", package: "LibOne"),
                .product(name: "LibTwo", package: "LibTwo"),
            ]
        ),
    ]
)
