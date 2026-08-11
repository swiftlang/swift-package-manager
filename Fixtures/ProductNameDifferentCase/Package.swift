// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TwoProductsHaveSameNameButDifferentCaseSensitivity",
    products: [
        .library(
            name: "MyProduct",
            targets: [
                "MyProduct",
            ],
        ),
        .executable(
            name: "myproduct",
            targets: [
                "execTargetNoMainFunction",
            ],
        ),
        .executable(
            name: "myProduct",
            targets: [
                "execTargetWithAtMain",
            ],
        ),
        .executable(
            name: "Myproduct",
            targets: [
                "execTargetNoAtMainButHasMainDotSwift",
            ],
        ),
    ],
    targets: [
        .target(
            name: "MyProduct",
        ),
        .executableTarget(
            name: "execTargetNoMainFunction",
        ),
        .executableTarget(
            name: "execTargetWithAtMain"
        ),
        .executableTarget(
            name: "execTargetNoAtMainButHasMainDotSwift"
        ),
    ],
)
