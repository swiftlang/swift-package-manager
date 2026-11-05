// swift-tools-version: 5.9
import PackageDescription

// A NON-root package that uses both majors: it depends on Shared 2.x directly and on LibOne (Shared 1.x).
// Its dependencies are reached through aliasing that was computed for the whole graph, not just for the
// root, so this checks that the per-consumer bucket choice also holds one level down.
let package = Package(
    name: "middle",
    products: [
        .library(name: "Middle", targets: ["Middle"]),
    ],
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "2.0.0"..<"3.0.0"),
        .package(path: "../../libs/LibOne"),
    ],
    targets: [
        .target(
            name: "Middle",
            dependencies: [
                .product(name: "Shared", package: "Shared"),
                .product(name: "LibOne", package: "LibOne"),
            ]
        ),
    ]
)
