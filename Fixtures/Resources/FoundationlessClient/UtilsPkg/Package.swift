// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "UtilsPkg",
    products: [
        .library(name: "Utils", targets: ["Utils"]),
    ],
    targets: [
        .target(name: "Utils", dependencies: [], resources: [
            .copy("foo.txt"),
        ]),
    ]
)
