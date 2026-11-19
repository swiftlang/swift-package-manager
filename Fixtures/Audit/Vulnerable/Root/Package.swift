// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Root",
    dependencies: [
        .package(url: "../Dep", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Root", dependencies: [.product(name: "Dep", package: "Dep")]),
    ]
)
