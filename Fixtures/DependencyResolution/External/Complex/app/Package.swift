// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Dealer",
    dependencies: [
        .package(url: "../deck-of-playing-cards", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Dealer",
            dependencies: ["DeckOfPlayingCards"],
            path: "./"),
    ]
)
