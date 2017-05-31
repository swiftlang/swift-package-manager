// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "EchoExecutable",
    products: [
        .executable(name: "exec1", targets: ["exec1"]),
        .executable(name: "exec2", targets: ["exec2"])
    ],
    targets: [
        .target(name: "exec1", dependencies: []),
        .target(name: "exec2", dependencies: [])
    ])