// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "ExeTest",
    targets: [
        .executableTarget(
            name: "Exe",
            dependencies: []
        ),
        .testTarget(
            name: "ExeTests",
            dependencies: ["Exe"]
        ),
    ]
)
