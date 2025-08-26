// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "Dealer",
    products: [
        .executable(
            name: "dealer",
            targets: ["dealer"]
        ),
    ] + .template(name: "TemplateExample"),
    dependencies: [
        .package(path: "../deck-of-playing-cards"),
    ],
    targets: [
        .executableTarget(
            name: "dealer",
        ),
    ] + .template(
        name: "TemplateExample",
        dependencies: [],
        initialPackageType: .executable,
        description: "Make your own Swift package template."
    ),
)
