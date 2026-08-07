// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "consumer-transitive",
    dependencies: [
        .package(path: "../consumer"),
    ],
    targets: [
        .executableTarget(
            name: "MyTransitiveApp",
            dependencies: [
                .product(name: "MyLib", package: "consumer"),
            ],
        ),
    ]
)
