// swift-tools-version: 5.9
import PackageDescription

// Root consumes Middle (which uses Shared 2.x and, through LibOne, Shared 1.x) and LibTwo (Shared 2.x),
// so Shared@2 is reached by two different packages and Shared@1 by one.
let package = Package(
    name: "nonroot-uses-both",
    dependencies: [
        .package(path: "../middle"),
        .package(path: "../../libs/LibTwo"),
    ],
    targets: [
        .executableTarget(
            name: "root",
            dependencies: [
                .product(name: "Middle", package: "middle"),
                .product(name: "LibTwo", package: "LibTwo"),
            ]
        ),
    ]
)
