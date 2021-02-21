// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "MySourceGenClient",
    dependencies: [
        .package(path: "../MySourceGenExtension")
    ],
    targets: [
        // A tool that uses an extension.
        .executableTarget(
            name: "MyTool",
            dependencies: [
                .product(name: "MySourceGenExt", package: "MySourceGenExtension")
            ]
        ),
        // A unit that uses the extension.
        .testTarget(
            name: "MyTests",
            dependencies: [
                .product(name: "MySourceGenExt", package: "MySourceGenExtension")
            ]
        )
    ]
)
