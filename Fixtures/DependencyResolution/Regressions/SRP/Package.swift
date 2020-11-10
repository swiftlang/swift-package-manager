// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SRP",
    products: [
        .library(name: "SRP", targets: ["SRP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/IBM-Swift/BlueCryptor.git", from: "0.8.16"),
        .package(url: "https://github.com/lorentey/BigInt.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "SRP", dependencies: ["Cryptor", "BigInt"], path: "Sources"),
        .testTarget(name: "SRPTests", dependencies: ["Cryptor", "SRP"]),
    ],
    swiftLanguageVersions: [4]
)
