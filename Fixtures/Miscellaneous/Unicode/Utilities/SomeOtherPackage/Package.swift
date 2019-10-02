// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "SomeOtherPackage",
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "SomeOtherPackage",
            dependencies: ["πשּׁµ𝄞🇺🇳🇮🇱x̱̱̱̱̱̄̄̄̄̄"]),
    ]
)
