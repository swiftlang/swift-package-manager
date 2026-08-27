// swift-tools-version: 999.0
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
