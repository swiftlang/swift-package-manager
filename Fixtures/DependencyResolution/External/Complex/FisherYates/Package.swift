// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FisherYates",
    products: [
        .library(name: "FisherYates", targets: ["FisherYates"]),
    ],
    targets: [
        .target(name: "FisherYates", path: "src"),
    ]
)
