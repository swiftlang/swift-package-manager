// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "UnknownPlatforms",
    targets: [
        .executableTarget(
            name: "UnknownPlatforms",
            swiftSettings: [
                .define("FOO", .when(platforms: [.custom("DoesNotExist")])),
		        .define("BAR", .when(platforms: [.linux])),
                .define("BAZ", .when(platforms: [.macOS])),
            ],
        ),
    ]
)
