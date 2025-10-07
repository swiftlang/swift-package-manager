// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "deck-of-playing-cards",
    products: [
        .executable(
            name: "deck",
            targets: ["Deck"]
        ),
    ],
    traits: [
        .trait(name: "trait3", description: "This trait is in a different package and not default.")
    ],
    targets: [
        .executableTarget(
            name: "Deck",
            path: "./"
        ),
    ]
)
