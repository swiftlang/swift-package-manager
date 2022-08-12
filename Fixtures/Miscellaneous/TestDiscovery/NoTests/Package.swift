// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Simple",
    targets: [
        .target(name: "Simple"),
        .testTarget(name: "SimpleTests", dependencies: ["Simple"]),
    ]
)
