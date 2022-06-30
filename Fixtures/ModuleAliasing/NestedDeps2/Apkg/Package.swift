// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Apkg",
    products: [
        .library(name: "A", targets: ["A"]),
    ],
    dependencies: [
        .package(path: "../Bpkg"),
        .package(path: "../Cpkg"),
    ],
    targets: [
        .target(name: "A",
                dependencies: [
                    .product(name: "Utils",
                             package: "Bpkg",
                             moduleAliases: ["Utils": "BUtils"]),
                    .product(name: "Utils",
                            package: "Cpkg",
                            moduleAliases: ["Utils": "CUtils"]),
                ]
               ),
    ]
)
