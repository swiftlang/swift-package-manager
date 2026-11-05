// swift-tools-version: 5.9
import PackageDescription

// The root pins Shared to 2.x and also uses LibOne (Shared 1.x) and LibTwo (Shared 2.x).
// Token from Shared 1.x and Token from Shared 2.x are different types that happen to share a source name.
let package = Package(
    name: "type-mismatch",
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "2.0.0"..<"3.0.0"),
        .package(path: "../libs/LibOne"),
        .package(path: "../libs/LibTwo"),
    ],
    targets: [
        .executableTarget(
            name: "mismatch",
            dependencies: [
                .product(name: "Shared", package: "Shared"),
                .product(name: "LibOne", package: "LibOne"),
                .product(name: "LibTwo", package: "LibTwo"),
            ]
        ),
    ]
)
