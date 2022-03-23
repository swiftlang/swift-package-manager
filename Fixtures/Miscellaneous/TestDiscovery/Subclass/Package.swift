// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "Subclass",
    targets: [
        .target(name: "Subclass"),
        .testTarget(name: "SubclassTests", dependencies: ["Subclass"]),
    ]
)
