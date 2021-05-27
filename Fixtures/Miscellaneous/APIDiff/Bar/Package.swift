// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Bar",
    products: [
        .library(name: "Baz", targets: ["Baz"]),
        .library(name: "Qux", targets: ["Qux"]),
    ],
    targets: [
        .target(name: "Baz"),
        .target(name: "Qux")
    ]
)
