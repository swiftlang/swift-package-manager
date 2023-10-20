// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "A",
    products: [
        .plugin(
            name: "A",
            targets: ["A"]),
    ],
    targets: [
        .plugin(
            name: "A",
            capability: .command(intent: .custom(
                verb: "A",
                description: "prints hello"
            ))
        ),
    ]
)
