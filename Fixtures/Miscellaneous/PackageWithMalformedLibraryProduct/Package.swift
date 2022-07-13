// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PackageWithMalformedLibraryProduct",
    products: [
        .library(
            name: "PackageWithMalformedLibraryProduct",
            targets: ["PackageWithMalformedLibraryProduct"]),
    ],
    targets: [
        .executableTarget(
            name: "PackageWithMalformedLibraryProduct")
    ]
)
