// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "Dealer",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v11),
        .watchOS(.v5)
    ],
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
