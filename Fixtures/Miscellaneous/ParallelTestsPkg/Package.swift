// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "ParallelTestsPkg",
    targets: [
        .target(
            name: "ParallelTestsPkg",
            dependencies: []),
        .testTarget(
            name: "ParallelTestsPkgTests",
            dependencies: ["ParallelTestsPkg"]),
    ]
)
