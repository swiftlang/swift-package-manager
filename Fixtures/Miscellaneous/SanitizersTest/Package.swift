// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SanitizersTest",
    products: [
    ],
    dependencies: [ ],
    targets: [
        .target(name: "executable", dependencies: ["BadCode"]),
        .target(name: "BadCode", dependencies: ["CLib"]),
        .target(name: "CLib", dependencies: []),
        .testTarget(name: "BadCodeTests", dependencies: ["BadCode"]),
    ]
)
