// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TestTargetDependOnTestTarget",
    targets: [
        .testTarget(
            name: "leafTestTarget",
        ),
        .testTarget(
            name: "myTestTarget",
            dependencies: [
                "leafTestTarget",
            ],
        ),
        .testTarget(
            name: "myOtherTestTarget",
            dependencies: [
                "leafTestTarget",
                "myTestTarget",
            ],
        ),
    ]
)
