// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "ExeTest",
    targets: [
        .target(
            name: "Exe",
            dependencies: []
        ),
        .testTarget(
            name: "ExeTests",
            dependencies: ["Exe"]
        ),
    ]
)
