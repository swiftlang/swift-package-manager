// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(path: "../../external/some-lib"),
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [
                .product(name: "SomeLib", package: "some-lib"),
            ],
        ),
    ],
)
