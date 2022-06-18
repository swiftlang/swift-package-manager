// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Bpkg",
    products: [
        .library(name: "Utils", type: .static, targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils",
                dependencies: []),
    ]
)
