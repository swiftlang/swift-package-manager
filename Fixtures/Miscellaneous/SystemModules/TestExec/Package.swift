// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "TestExec",
    dependencies: [
        .package(url: "../CFake", from: "1.0.0"),
    ],
    targets: [
        .target(name: "TestExec", path: "Sources"),
    ]
)
