// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "deck-of-playing-cards",
    products: [
        .executable(
            name: "deck",
            targets: ["Deck"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Deck",
            path: "./"
        ),
    ]
)
