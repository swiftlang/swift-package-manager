// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "PlayingCard",
    products: [
        .library(name: "PlayingCard", targets: ["PlayingCard"]),
    ],
    targets: [
        .target(name: "PlayingCard", path: "src"),
    ]
)
