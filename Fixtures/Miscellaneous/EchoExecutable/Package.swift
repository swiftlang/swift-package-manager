// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "EchoExecutable",
    products: [
        .executable(name: "secho", targets: ["secho"])
    ],
    targets: [
        .target(name: "secho", dependencies: [])
    ])