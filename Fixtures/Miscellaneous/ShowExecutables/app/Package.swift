// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Dealer",
    products: [
        .executable(
            name: "dealer",
            targets: ["Dealer"]
        ),
    ],
    dependencies: [
        .package(path: "../deck-of-playing-cards"),
    ],
    targets: [
        .executableTarget(
            name: "Dealer",
            path: "./"
        ),
    ]
)
