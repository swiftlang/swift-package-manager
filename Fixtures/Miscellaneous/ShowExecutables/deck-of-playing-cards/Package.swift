// swift-tools-version:999.0.0
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
