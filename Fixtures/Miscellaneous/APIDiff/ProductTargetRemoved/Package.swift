// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ProductTargetRemoved",
    products: [
        .library(name: "ProductTargetRemoved", targets: ["Foo", "Bar"]),
    ],
    targets: [
        .target(name: "Foo"),
        .target(name: "Bar"),
    ]
)
