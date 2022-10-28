// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "UtilsPkg",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: []),
    ]
)
