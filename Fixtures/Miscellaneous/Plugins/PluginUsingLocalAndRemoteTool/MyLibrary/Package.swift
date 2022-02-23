// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyLibrary",
    dependencies: [
        .package(path: "../MyPlugin")
    ],
    targets: [
        .target(
            name: "MyLibrary"
        ),
        .testTarget(
            name: "MyLibraryTests",
            dependencies: ["MyLibrary"]
        )
    ]
)
