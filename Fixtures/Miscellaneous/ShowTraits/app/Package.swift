// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Dealer",
    products: [
        .executable(
            name: "dealer",
            targets: ["Dealer"]
        ),
    ],
    traits: [
        .trait(name: "trait1", description: "this trait is the default in app"),
        .trait(name: "trait2", description: "this trait is not the default in app"),
        .default(enabledTraits: ["trait1"]),
    ],
    dependencies: [
        .package(path: "../deck-of-playing-cards", traits: ["trait3"]),
    ],
    targets: [
        .executableTarget(
            name: "Dealer",
            path: "./"
        ),
    ]
)
