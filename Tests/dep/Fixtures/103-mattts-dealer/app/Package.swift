import PackageDescription

let package = Package(
    name: "Dealer",
    dependencies: [
        .Package(url: "../deck-of-playing-cards", versions: Version(1,1,0)..<Version(2,0,0)),
        .Package(url: "../PlayingCard", versions: Version(1,1,0)..<Version(2,0,0)),
        .Package(url: "../FisherYates", versions: Version(1,2,0)..<Version(2,0,0))
    ]
)
