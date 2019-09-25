// swift-tools-version:4.2
import PackageDescription
let package = Package(
    name: "DynamicLibrary",
    products: [
        .library(
            name: "DynamicLibrary",
            type: .dynamic,
            targets: ["DynamicLibrary"]),
    ],
    targets: [
        .target(
            name: "DynamicLibrary"),
    ]
)
