// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "MixedSourceTestTarget",
    targets: [
        .target(name: "Calculator"),
        .testTarget(name: "CalculatorTests", dependencies: ["Calculator"]),
    ]
)
