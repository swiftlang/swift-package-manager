// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dep",
    products: [
        .library(name: "Dep", targets: ["Dep"]),
    ],
    targets: [
        .target(name: "Dep"),
    ]
)
