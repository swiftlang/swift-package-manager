// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Root",
    dependencies: [
        .package(path: "../Local"),
    ],
    targets: [
        .target(name: "Root", dependencies: [.product(name: "Local", package: "Local")]),
    ]
)
