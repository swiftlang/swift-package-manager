// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "root",
    dependencies: [
        .package(url: "../dep2", from: "1.0.0"),
    ],
    targets: [
        .target(name: "root", dependencies: ["dep2"], path: "./"),
    ]
)

