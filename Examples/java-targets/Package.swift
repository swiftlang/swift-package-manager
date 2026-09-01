// swift-tools-version: 6.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "java-targets",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.5.0"),
    ],
    targets: [
        .custom(
            name: "JavaTarget",
            plugins: [
                "JavaBuilderPlugin",
            ]
        ),
        .plugin(
            name: "JavaBuilderPlugin",
            capability: .buildTool,
            dependencies: [
                "JavaBuilder"
            ]
        ),
        .executableTarget(
            name: "JavaBuilder",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
        .custom(name: "JarTarget",
            dependencies: [
                "JavaTarget",
            ],
            plugins: [
                "JarBuilderPlugin",
            ]
        ),
        .plugin(
            name: "JarBuilderPlugin",
            capability: .buildTool,
            dependencies: [
                "JarBuilder"
            ]
        ),
        .executableTarget(
            name: "JarBuilder",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
