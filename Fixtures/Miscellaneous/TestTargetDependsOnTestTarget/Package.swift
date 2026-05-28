// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TestTargetDependsOnTestTarget",
    targets: [
        .target(name: "MyLib"),
        .testTarget(name: "TestUtils", dependencies: ["MyLib"]),
        .testTarget(name: "FooTests", dependencies: ["TestUtils"]),
        .testTarget(name: "BarTests", dependencies: ["TestUtils"]),
    ]
)
