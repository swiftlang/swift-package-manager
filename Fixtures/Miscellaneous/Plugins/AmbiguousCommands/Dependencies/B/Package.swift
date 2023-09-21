// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "B",
    products: [
        .plugin(
            name: "B",
            targets: ["B"]),
    ],
    targets: [
        .plugin(
            name: "B",
            capability: .command(intent: .custom(
                verb: "A",
                description: "prints hello"
            ))
        ),
    ]
)
