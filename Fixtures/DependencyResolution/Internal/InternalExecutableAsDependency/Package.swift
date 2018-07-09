// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Simple",
    targets: [
        .target(name: "Foo", dependencies: ["Bar"], path: "Foo"),
        .target(name: "Bar", path: "Bar"),
    ]
)
