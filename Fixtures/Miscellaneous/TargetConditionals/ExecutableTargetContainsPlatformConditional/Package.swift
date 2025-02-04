// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ExecutableTargetWhen",
    products: [
        .executable(
            name: "test",
            targets: ["ExecutableTargetWhen"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "ExecutableTargetWhen",
            dependencies: [
                .target(name:"LinuxOnly", condition: .when(platforms:[.linux])),
                .target(name:"MacOSOnly", condition: .when(platforms:[.macOS])),
                .target(name:"WindowsOnly", condition: .when(platforms:[.windows])),
                .target(name:"AllPlatforms")
            ]
        ),
        .target(
            name: "AllPlatforms"
        ),
        .target(
            name: "LinuxOnly",
            dependencies: [
                "CLibArchive",
                "AllPlatforms"
            ]
        ),
        .target(
            name: "MacOSOnly",
            dependencies: [
                "AllPlatforms"
            ]
        ),
        .target(
            name: "WindowsOnly",
            dependencies: [
                "AllPlatforms"
            ]
        ),
        .systemLibrary(
            name: "CLibArchive",
            pkgConfig: "libarchive",
            providers: [
                .apt(["libarchive-dev"]),
            ]
        ),
    ]
)
