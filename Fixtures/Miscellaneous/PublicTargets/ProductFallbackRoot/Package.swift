// swift-tools-version: 6.0
import PackageDescription

// Dep has no products, so these product dependencies fall back to its public targets.
let package = Package(
    name: "ProductFallbackRoot",
    dependencies: [
        .package(path: "../Dep"),
    ],
    targets: [
        .executableTarget(
            name: "Tool",
            dependencies: [
                .product(name: "PublicLib", package: "Dep"),
                .product(name: "PublicPlain", package: "Dep"),
            ]
        ),
    ]
)
