// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "package-registry-example",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "RegistryExample",
            targets: ["RegistryExample"]
        ),
        .executable(
            name: "PackageRegistryServer",
            targets: ["PackageRegistryServer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "RegistryExample",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux, .android, .windows, .wasi, .openbsd])
                ),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "PackageRegistryServer",
            dependencies: [
                "RegistryExample",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "RegistryExampleTests",
            dependencies: [
                "RegistryExample",
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6]
)
