// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "../CFoo", from: "1.0.0"),
    ],
    targets: [
        .target(name: "App", path: "./"),
    ]
)
