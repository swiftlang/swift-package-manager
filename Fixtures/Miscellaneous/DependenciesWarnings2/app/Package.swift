// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "app",
    products: [
        .executable(name: "app", targets: ["app"])
    ],
    dependencies: [
        .package(url: "../dep1", from: "1.0.0"),
        .package(url: "../dep2", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
          name: "app",
          dependencies: [
            .product(name: "dep1", package: "dep1"),
            .product(name: "dep2", package: "dep2")
          ],
          path: "./"
        )
    ]
)
