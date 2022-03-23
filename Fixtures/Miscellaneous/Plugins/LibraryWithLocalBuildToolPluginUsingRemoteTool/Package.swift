// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyLibrary",
    dependencies: [
        .package(path: "../MySourceGenPlugin")
    ],
    targets: [
        .plugin(
            name: "MyLocalSourceGenBuildToolPlugin",
            capability: .buildTool(),
            dependencies: [
                .product(name: "MySourceGenBuildTool", package: "MySourceGenPlugin")
            ]
        ),
        .target(
            name: "MyLibrary",
            plugins: [
                "MyLocalSourceGenBuildToolPlugin",
            ]
        ),
        .testTarget(
            name: "MyLibraryTests",
            dependencies: ["MyLibrary"]
        )
    ]
)
