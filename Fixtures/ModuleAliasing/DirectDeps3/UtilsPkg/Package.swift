// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "UtilsPkg",
    products: [
        .library(name: "Lib", targets: ["Lib", "Utils"])
    ],
    targets: [
        .target(name: "Utils", dependencies: []),
        .target(name: "Lib", dependencies: ["Utils"])
    ]
)
