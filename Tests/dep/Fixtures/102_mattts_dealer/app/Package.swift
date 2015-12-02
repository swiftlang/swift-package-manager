import PackageDescription

let package = Package(
    name: "Dealer",
    dependencies: [
        .Package(url: "../DeckOfPlayingCards", versions: Version(1,1,0)..<Version(2,0,0))
    ]
)
