// swift-tools-version:5.1
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
