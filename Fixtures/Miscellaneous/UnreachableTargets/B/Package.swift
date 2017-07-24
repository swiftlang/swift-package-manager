// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "B",
    products: [
        .library(name: "BLibrary", targets: ["BTarget1"]),
		.executable(name: "bexec", targets: ["BTarget2"])
    ],
    targets: [
        .target(name: "BTarget1", dependencies: []),
		.target(name: "BTarget2", dependencies: [])
    ])
