// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "BPkg",
    products: [
        .library(name: "UtilsInB", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: [])
    ]
)
