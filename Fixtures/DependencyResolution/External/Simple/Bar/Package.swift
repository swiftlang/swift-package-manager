// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Bar",
    dependencies: [
        .package(url: "../Foo", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Bar", dependencies: ["Foo"], path: "./"),
    ]
)
