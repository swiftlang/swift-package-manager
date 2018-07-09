// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "DeckOfPlayingCards",
    products: [
        .library(name: "DeckOfPlayingCards", targets: ["DeckOfPlayingCards"]),
    ],
    dependencies: [
        .package(url: "../PlayingCard", from: "1.0.0"),
        .package(url: "../FisherYates", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "DeckOfPlayingCards",
            dependencies: ["PlayingCard", "FisherYates"],
            path: "src"),
    ]
)
