// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Bar",
    dependencies: [
        .package(url: "../NonExistantPackage", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Bar", path: "./"),
    ]
)
