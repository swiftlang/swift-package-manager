// swift-tools-version: 999.0
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
