// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Foo",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "Foo", targets: ["Foo"]),
    ],
    targets: [
        .target(name: "Foo", path: "./"),
    ]
)
