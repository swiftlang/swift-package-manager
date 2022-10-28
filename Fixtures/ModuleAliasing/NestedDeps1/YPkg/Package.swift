// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "YPkg",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: [])
    ]
)
