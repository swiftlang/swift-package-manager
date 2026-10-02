// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(url: "../../external/some-lib", from: "1.0.0"),
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
