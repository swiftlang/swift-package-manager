// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "consumer",
    products: [
        // Expose MyLib as a product so downstream packages (e.g.
        // `consumer-transitive`) can depend on it and thereby transitively
        // reach `PaperExperimental` from the producer.
        .library(
            name: "MyLib",
            targets: ["MyLib"],
        ),
    ],
    dependencies: [
        .package(path: "../producer"),
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "PaperLegacy", package: "producer"),
            ],
        ),
        .target(
            name: "MyLib",
            dependencies: [
                .product(name: "PaperExperimental", package: "producer"),
            ],
            swiftSettings: [
                .treatAllWarnings(as: .error),
            ],
        ),
    ]
)
