// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "EchoExecutable",
    products: [
        .executable(name: "secho", targets: ["secho"])
    ],
    targets: [
        .target(name: "secho", dependencies: []),
        .testTarget(name: "TestSuite")
    ])
