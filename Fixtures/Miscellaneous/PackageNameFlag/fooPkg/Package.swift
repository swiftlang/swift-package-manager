// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "fooPkg",
    products: [
        .library(name: "Foo", targets: ["Foo"]),
    ],
    targets: [
        .target(name: "Foo", dependencies: ["Zoo"]),
        .target(name: "Zoo"),
    ]
)
