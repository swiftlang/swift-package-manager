// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "foo",
    dependencies: [
        .package(url: "../bar", from: "1.0.0"),
        .package(url: "../baz", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "foo",
            dependencies: ["bar", "baz"],
            path: "Sources"),
    ]
)
