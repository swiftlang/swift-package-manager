// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "downstream",
    dependencies: [
        .package(url: "../upstream", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Downstream",
            dependencies: [
                .product(name: "Upstream", package: "upstream"),
            ]
        ),
    ]
)
