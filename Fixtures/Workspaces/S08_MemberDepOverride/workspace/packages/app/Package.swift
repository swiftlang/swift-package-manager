// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "app",
    dependencies: [
        .package(url: "https://github.com/nonexistent/some-dep", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "app",
            dependencies: [
                .product(name: "SomeDep", package: "some-dep"),
            ],
        ),
    ],
)
