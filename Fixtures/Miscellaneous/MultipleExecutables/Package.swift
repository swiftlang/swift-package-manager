// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "EchoExecutable",
    products: [
        .executable(name: "exec1", targets: ["exec1"]),
        .executable(name: "exec2", targets: ["exec2"]),
        .library(name: "lib1", targets: ["lib1"]),
    ],
    targets: [
        .target(name: "exec1", dependencies: ["lib1"]),
        .target(name: "exec2", dependencies: ["lib1"]),
        .target(name: "lib1"),
    ]
)