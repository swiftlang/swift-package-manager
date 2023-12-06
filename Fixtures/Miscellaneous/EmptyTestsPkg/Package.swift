// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "EmptyTestsPkg",
    targets: [
        .target(
            name: "EmptyTestsPkg",
            dependencies: []),
        .testTarget(
            name: "EmptyTestsPkgTests",
            dependencies: ["EmptyTestsPkg"]),
    ]
)
