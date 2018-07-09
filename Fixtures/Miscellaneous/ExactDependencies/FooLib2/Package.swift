// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FooLib2",
    products: [
        .library(name: "FooLib2", targets: ["FooLib2"]),
    ],
    targets: [
        .target(name: "FooLib2", path: "./"),
    ]
)
