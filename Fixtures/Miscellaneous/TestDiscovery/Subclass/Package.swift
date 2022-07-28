// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "Subclass",
    targets: [
        .target(name: "Subclass"),
        .testTarget(name: "Module1Tests", dependencies: ["Subclass"]),
        .testTarget(name: "Module2Tests", dependencies: ["Subclass"]),
    ]
)
