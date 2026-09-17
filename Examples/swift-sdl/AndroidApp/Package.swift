// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "AndroidApp",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-system", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AndroidApp",
            dependencies: [
                .product(name: "AndroidExample", package: "swift-sdl"),
            ],
            plugins: ["ApkBuilderPlugin"]
        ),
        .plugin(
            name: "ApkBuilderPlugin",
            capability: .buildTool(),
            dependencies: ["ApkBuilder"]
        ),
        .executableTarget(
            name: "ApkBuilder",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        )
    ]
)
