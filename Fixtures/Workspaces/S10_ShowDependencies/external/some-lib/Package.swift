// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "some-lib",
    products: [
        .library(name: "SomeLib", targets: ["SomeLib"]),
    ],
    targets: [
        .target(name: "SomeLib"),
    ],
)
