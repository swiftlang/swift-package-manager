// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .library(name: "Foo", targets: ["Foo", "XCFramework"]),
    ],
    targets: [
        .target(name: "Foo", path: "./Foo"),
        .binaryTarget(name: "XCFramework", path: "./Foo.xcframework")
    ]
)
