// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Inner",
    products: [
        .library(
          name: "InnerBar",
          targets: ["InnerBar"]
        ),
    ],
    targets: [
        .binaryTarget(name: "InnerBar", path: "./InnerBar.xcframework"),
    ]
)
