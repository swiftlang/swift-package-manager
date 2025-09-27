// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dealer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v5)
    ],
    dependencies: [
        .package(path: "../PlayingCard"),
    ],
    targets: [
        .target(
            name: "Dealer",
            dependencies: ["PlayingCard"],
            path: "./"
        ),
    ]
)
