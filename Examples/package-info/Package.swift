// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "package-info",
    dependencies: [
        .package(url: "https://github.com/apple/swift-package-manager.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "package-info",
            dependencies: ["SwiftPM"]),
    ]
)
