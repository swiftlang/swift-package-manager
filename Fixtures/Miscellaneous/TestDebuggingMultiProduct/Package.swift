// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestDebuggingMultiProduct",
    targets: [
        .target(name: "LibA"),
        .target(name: "LibB"),
        .testTarget(name: "LibATests", dependencies: ["LibA"]),
        .testTarget(name: "LibBTests", dependencies: ["LibB"]),
    ]
)
