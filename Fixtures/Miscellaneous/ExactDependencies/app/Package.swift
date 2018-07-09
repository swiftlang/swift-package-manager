// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "28_exact_dependencies",
    dependencies: [
        .package(url: "../FooExec", from: "1.0.0"),
    ],
    targets: [
        .target(name: "28_exact_dependencies", dependencies: ["FooExec"], path: "./"),
    ]
)

