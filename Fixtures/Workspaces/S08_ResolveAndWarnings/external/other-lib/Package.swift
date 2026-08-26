// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "other-lib",
    products: [
        .library(name: "OtherLib", targets: ["OtherLib"]),
    ],
    targets: [
        .target(name: "OtherLib"),
    ],
)
