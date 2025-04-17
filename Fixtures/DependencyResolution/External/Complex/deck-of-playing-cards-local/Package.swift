// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "DeckOfPlayingCards",
    products: [
        .library(name: "DeckOfPlayingCards", targets: ["DeckOfPlayingCards"]),
    ],
    dependencies: [
        .package(path: "../PlayingCard"),
        .package(path: "../FisherYates")
    ],
    targets: [
        .target(
            name: "DeckOfPlayingCards",
            dependencies: ["PlayingCard", "FisherYates"],
            path: "src"),
    ]
)
