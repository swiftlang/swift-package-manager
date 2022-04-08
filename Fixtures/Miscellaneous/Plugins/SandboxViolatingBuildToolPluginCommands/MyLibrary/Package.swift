// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyLibrary",
    dependencies: [
        .package(path: "../MyPlugin")
    ],
    targets: [
        .target(
            name: "MyLibrary",
            plugins: [
                .plugin(name: "PackageScribblerPlugin", package: "MyPlugin")
            ])
    ]
)
