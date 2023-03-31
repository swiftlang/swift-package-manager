// swift-tools-version:999.0
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
