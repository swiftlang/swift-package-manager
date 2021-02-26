// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "MySourceGenClient",
    dependencies: [
        .package(path: "../MySourceGenPlugin")
    ],
    targets: [
        // A tool that uses an plugin.
        .executableTarget(
            name: "MyTool",
            dependencies: [
                .product(name: "MySourceGenPlugin", package: "MySourceGenPlugin")
            ]
        ),
        // A unit that uses the plugin.
        .testTarget(
            name: "MyTests",
            dependencies: [
                .product(name: "MySourceGenPlugin", package: "MySourceGenPlugin")
            ]
        )
    ]
)
