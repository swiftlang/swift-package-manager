// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestDebugging",
    targets: [
        .target(name: "TestDebugging"),
        .testTarget(name: "TestDebuggingTests", dependencies: ["TestDebugging"]),
    ]
)