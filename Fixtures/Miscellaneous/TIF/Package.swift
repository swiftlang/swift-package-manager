// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "TIF",
    products: [
        .library(name: "TIF", targets: ["TIF"])
    ],
    targets: [
        .target(
            name: "TIF",
            resources: [
                .copy("some.txt")
            ]
        ),
    ]
)
