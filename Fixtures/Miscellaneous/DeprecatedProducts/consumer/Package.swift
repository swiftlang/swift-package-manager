// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "consumer",
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
