// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "dep2",
    products: [
        .executable(name: "dep2", targets: ["dep2"]),
    ],
    dependencies: [
        .package(url: "../dep1", from: "1.0.0"),
    ],
    targets: [
        .target(name: "dep2", dependencies:[ "dep1"], path: "./"),
    ]
)
