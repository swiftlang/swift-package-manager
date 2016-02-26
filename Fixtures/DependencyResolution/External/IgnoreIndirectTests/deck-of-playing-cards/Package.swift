import PackageDescription

let package = Package(
    name: "DeckOfPlayingCards",
    dependencies: [
        .Package(url: "../PlayingCard", majorVersion: 1),
        .Package(url: "../FisherYates", majorVersion: 1)
    ]
)
