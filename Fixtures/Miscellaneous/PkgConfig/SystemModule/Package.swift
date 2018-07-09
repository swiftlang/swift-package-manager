// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "SystemModule",
    products: [
        .library(name: "SystemModule", targets: ["SystemModule"]),
    ],
    targets: [
        .target(name: "SystemModule", path: "Sources"),
    ]
)
