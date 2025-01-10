// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Sample",
    products: [
        .library(
            name: "Sample",
            targets: ["Sample"]
        ),
    ],
    targets: [
        .target(
            name: "CSample",
            sources: ["./vendorsrc/src"],
            cSettings: [
                .headerSearchPath("./vendorsrc/include"),
            ]
        ),
        .target(
            name: "Sample",
            dependencies: ["CSample"]
        ),
    ]
)
